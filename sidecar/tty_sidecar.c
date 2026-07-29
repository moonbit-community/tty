/*
 * tty-sidecar: terminal syscall proxy for the MoonBit wasm backend.
 *
 * The wasm host (moonrun) has no libc surface for termios/ioctl/isatty, so
 * the wasm program spawns this sidecar with stdin/stdout/stderr inherited
 * and proxies terminal operations to it over loopback TCP. See PROTOCOL.md
 * in this directory for the wire format.
 *
 * Structure:
 * - Unix: single thread; poll() over the control socket and a SIGWINCH
 *   self-pipe. The event socket is non-blocking and resize events are
 *   coalesced (latest size wins), so a parent that stops draining events
 *   can never stall the control loop.
 * - Windows: two threads. The main thread runs the blocking control loop;
 *   a console thread (started by WATCH) is the console's sole input
 *   consumer and streams raw INPUT_RECORDs over the event connection with
 *   blocking sends — backpressure lands in the console input buffer.
 *
 * Single translation unit, C99, no dependencies beyond libc (and ws2_32 on
 * Windows). Cross-compiled with `zig cc` for linux/amd64, macos/arm64 and
 * windows/amd64 by the MoonBit build tool in `tools/`.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
typedef SOCKET socket_t;
#define INVALID_SOCKET_VALUE INVALID_SOCKET
/* Error payloads carry GetLastError values on Windows. */
#define PROTO_EINVAL ERROR_INVALID_PARAMETER
/* The parent slices record batches in 20-byte steps (INPUT_RECORD_SIZE). */
typedef char assert_input_record_is_20_bytes[sizeof(INPUT_RECORD) == 20 ? 1
                                                                        : -1];
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <termios.h>
#include <unistd.h>
typedef int socket_t;
#define INVALID_SOCKET_VALUE (-1)
#define PROTO_EINVAL EINVAL
#endif

#define PROTO_VERSION 1
#define MAGIC_CONTROL 0x4354544Du /* "MTTC" little-endian */
#define MAGIC_EVENT 0x4554544Du   /* "MTTE" little-endian */

#define OP_ISATTY 0x01
#define OP_ENTER_RAW 0x02
#define OP_LEAVE_RAW 0x03
#define OP_WINSIZE 0x05
#define OP_WATCH 0x06
#define OP_SHUTDOWN 0x07

#define KIND_OK 0
#define KIND_ERR 1
#define KIND_EVENT 2

#define EVENT_RESIZE 1
#define EVENT_INPUT_RECORDS 2

#define MAX_PAYLOAD 4096
#define MAX_TOKEN 256

typedef struct tty_state {
#ifdef _WIN32
  uint32_t input_mode;
  uint32_t output_mode;
  int32_t has_output_mode;
#else
  struct termios termios;
#endif
} tty_state_t;

static socket_t control_sock = INVALID_SOCKET_VALUE;
static socket_t event_sock = INVALID_SOCKET_VALUE;

/* Terminal-restore safety net: state captured by the first ENTER_RAW,
 * restored on abnormal disconnect while raw mode is still active. */
static tty_state_t original_state;
static int has_original_state = 0;
static uint8_t original_input_slot = 0;
static uint8_t original_output_slot = 1;
static int state_dirty = 0;

static int watch_enabled = 0;

static int32_t
last_error(void) {
#ifdef _WIN32
  return (int32_t)GetLastError();
#else
  return (int32_t)errno;
#endif
}

static void
set_error(int32_t code) {
#ifdef _WIN32
  SetLastError((DWORD)code);
#else
  errno = (int)code;
#endif
}

/* ---------- socket I/O ---------- */

static int
send_all(socket_t sock, const uint8_t *data, size_t len) {
  while (len > 0) {
#ifdef _WIN32
    int n = send(sock, (const char *)data, (int)len, 0);
    if (n == SOCKET_ERROR) {
      return -1;
    }
#else
    ssize_t n = send(sock, data, len, 0);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
#endif
    data += n;
    len -= (size_t)n;
  }
  return 0;
}

static int
recv_all(socket_t sock, uint8_t *data, size_t len) {
  while (len > 0) {
#ifdef _WIN32
    int n = recv(sock, (char *)data, (int)len, 0);
    if (n == SOCKET_ERROR) {
      return -1;
    }
#else
    ssize_t n = recv(sock, data, len, 0);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
#endif
    if (n == 0) {
      return -1; /* EOF */
    }
    data += n;
    len -= (size_t)n;
  }
  return 0;
}

static void
put_u16(uint8_t *dst, uint16_t value) {
  dst[0] = (uint8_t)(value & 0xFF);
  dst[1] = (uint8_t)(value >> 8);
}

static void
put_u32(uint8_t *dst, uint32_t value) {
  dst[0] = (uint8_t)(value & 0xFF);
  dst[1] = (uint8_t)((value >> 8) & 0xFF);
  dst[2] = (uint8_t)((value >> 16) & 0xFF);
  dst[3] = (uint8_t)((value >> 24) & 0xFF);
}

static uint16_t
get_u16(const uint8_t *src) {
  return (uint16_t)(src[0] | (src[1] << 8));
}

static uint32_t
get_u32(const uint8_t *src) {
  return (uint32_t)src[0] | ((uint32_t)src[1] << 8) |
         ((uint32_t)src[2] << 16) | ((uint32_t)src[3] << 24);
}

static void
fill_frame_header(
  uint8_t *dst,
  uint8_t kind,
  uint32_t req_id,
  uint16_t len
) {
  dst[0] = kind;
  put_u32(dst + 1, req_id);
  put_u16(dst + 5, len);
}

static int
send_frame(
  socket_t sock,
  uint8_t kind,
  uint32_t req_id,
  const uint8_t *payload,
  uint16_t len
) {
  uint8_t header[7];
  fill_frame_header(header, kind, req_id, len);
  if (send_all(sock, header, sizeof(header)) < 0) {
    return -1;
  }
  if (len > 0 && send_all(sock, payload, len) < 0) {
    return -1;
  }
  return 0;
}

static int
send_ok(uint32_t req_id, const uint8_t *payload, uint16_t len) {
  return send_frame(control_sock, KIND_OK, req_id, payload, len);
}

static int
send_err(uint32_t req_id, int32_t code) {
  uint8_t payload[4];
  put_u32(payload, (uint32_t)code);
  return send_frame(control_sock, KIND_ERR, req_id, payload, sizeof(payload));
}

/* ---------- terminal operations ---------- */

#ifdef _WIN32

static HANDLE
slot_handle(uint8_t slot) {
  switch (slot) {
    case 0: return GetStdHandle(STD_INPUT_HANDLE);
    case 1: return GetStdHandle(STD_OUTPUT_HANDLE);
    case 2: return GetStdHandle(STD_ERROR_HANDLE);
    default: return INVALID_HANDLE_VALUE;
  }
}

static int
op_isatty(uint8_t slot, int *is_tty) {
  HANDLE handle = slot_handle(slot);
  DWORD mode;
  if (GetConsoleMode(handle, &mode)) {
    *is_tty = 1;
    return 0;
  }
  DWORD console_error = GetLastError();
  DWORD file_type = GetFileType(handle);
  if (file_type != FILE_TYPE_UNKNOWN || GetLastError() == NO_ERROR) {
    *is_tty = 0;
    return 0;
  }
  SetLastError(console_error);
  return -1;
}

static int
op_get_state(uint8_t input_slot, uint8_t output_slot, tty_state_t *state) {
  DWORD mode;
  if (!GetConsoleMode(slot_handle(input_slot), &mode)) {
    return -1;
  }
  state->input_mode = (uint32_t)mode;
  state->output_mode = 0;
  state->has_output_mode = 0;
  if (GetConsoleMode(slot_handle(output_slot), &mode)) {
    state->output_mode = (uint32_t)mode;
    state->has_output_mode = 1;
  }
  return 0;
}

static int
op_set_state(
  uint8_t input_slot,
  uint8_t output_slot,
  const tty_state_t *state
) {
  if (!SetConsoleMode(slot_handle(input_slot), (DWORD)state->input_mode)) {
    return -1;
  }
  if (state->has_output_mode &&
      !SetConsoleMode(slot_handle(output_slot), (DWORD)state->output_mode)) {
    return -1;
  }
  return 0;
}

static void
op_make_raw(const tty_state_t *state, tty_state_t *raw) {
  *raw = *state;
  DWORD mode = (DWORD)state->input_mode;
  mode &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT);
#ifdef ENABLE_EXTENDED_FLAGS
  mode |= ENABLE_EXTENDED_FLAGS;
#endif
#ifdef ENABLE_QUICK_EDIT_MODE
  mode &= ~ENABLE_QUICK_EDIT_MODE;
#endif
#ifdef ENABLE_VIRTUAL_TERMINAL_INPUT
  mode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
#endif
#ifdef ENABLE_WINDOW_INPUT
  mode |= ENABLE_WINDOW_INPUT;
#endif
  raw->input_mode = (uint32_t)mode;
  if (raw->has_output_mode) {
    DWORD output_mode = (DWORD)state->output_mode;
#ifdef ENABLE_PROCESSED_OUTPUT
    output_mode |= ENABLE_PROCESSED_OUTPUT;
#endif
#ifdef ENABLE_VIRTUAL_TERMINAL_PROCESSING
    output_mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
#endif
#ifdef DISABLE_NEWLINE_AUTO_RETURN
    output_mode |= DISABLE_NEWLINE_AUTO_RETURN;
#endif
    raw->output_mode = (uint32_t)output_mode;
  }
}

static int
op_winsize(uint8_t slot, int32_t *rows, int32_t *cols) {
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(slot_handle(slot), &info)) {
    return -1;
  }
  int32_t height = (int32_t)(info.srWindow.Bottom - info.srWindow.Top + 1);
  int32_t width = (int32_t)(info.srWindow.Right - info.srWindow.Left + 1);
  if (height <= 0 || width <= 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }
  *rows = height;
  *cols = width;
  return 0;
}

#else /* !_WIN32 */

static int
op_isatty(uint8_t slot, int *is_tty) {
  errno = 0;
  if (isatty((int)slot)) {
    *is_tty = 1;
    return 0;
  }
  if (errno == 0 || errno == ENOTTY) {
    *is_tty = 0;
    return 0;
  }
  return -1;
}

static int
op_get_state(uint8_t input_slot, uint8_t output_slot, tty_state_t *state) {
  (void)output_slot;
  if (tcgetattr((int)input_slot, &state->termios) < 0) {
    return -1;
  }
  return 0;
}

static int
op_set_state(
  uint8_t input_slot,
  uint8_t output_slot,
  const tty_state_t *state
) {
  (void)output_slot;
  if (tcsetattr((int)input_slot, TCSANOW, &state->termios) < 0) {
    return -1;
  }
  return 0;
}

static void
op_make_raw(const tty_state_t *state, tty_state_t *raw) {
  *raw = *state;
  raw->termios.c_iflag &= (tcflag_t)~(IGNBRK | BRKINT | PARMRK | ISTRIP |
                                      INLCR | IGNCR | ICRNL | IXON);
  raw->termios.c_oflag &= (tcflag_t)~OPOST;
  raw->termios.c_lflag &=
    (tcflag_t)~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  raw->termios.c_cflag &= (tcflag_t)~(CSIZE | PARENB);
  raw->termios.c_cflag |= CS8;
  raw->termios.c_cc[VMIN] = 1;
  raw->termios.c_cc[VTIME] = 0;
}

static int
op_winsize(uint8_t slot, int32_t *rows, int32_t *cols) {
  struct winsize size;
  if (ioctl((int)slot, TIOCGWINSZ, &size) < 0) {
    return -1;
  }
  if (size.ws_row <= 0 || size.ws_col <= 0) {
    errno = EINVAL;
    return -1;
  }
  *rows = (int32_t)size.ws_row;
  *cols = (int32_t)size.ws_col;
  return 0;
}

#endif /* _WIN32 */

/* ---------- event delivery ---------- */

#ifdef _WIN32

/* Console input thread: sole consumer of the console input buffer while
 * watching is enabled. Blocking sends provide backpressure; the thread ends
 * when the parent disappears (send fails) or the console goes away. */
static DWORD WINAPI
console_input_thread(LPVOID param) {
  (void)param;
  HANDLE console = GetStdHandle(STD_INPUT_HANDLE);
  INPUT_RECORD records[64];
  uint8_t payload[1 + sizeof(records)];
  for (;;) {
    DWORD count = 0;
    if (!ReadConsoleInputW(console, records, 64, &count)) {
      return 0;
    }
    if (count == 0) {
      continue;
    }
    payload[0] = EVENT_INPUT_RECORDS;
    memcpy(payload + 1, records, count * sizeof(INPUT_RECORD));
    if (send_frame(
          event_sock, KIND_EVENT, 0, payload,
          (uint16_t)(1 + count * sizeof(INPUT_RECORD))
        ) < 0) {
      return 0;
    }
  }
}

static HANDLE console_thread = NULL;

static void
start_watching(void) {
  if (console_thread == NULL) {
    console_thread =
      CreateThread(NULL, 0, console_input_thread, NULL, 0, NULL);
  }
}

#else /* !_WIN32 */

static int sigwinch_pipe[2] = {-1, -1};

static void
sigwinch_handler(int signo) {
  (void)signo;
  int saved_errno = errno;
  uint8_t byte = 1;
  ssize_t rc;
  do {
    rc = write(sigwinch_pipe[1], &byte, 1);
  } while (rc < 0 && errno == EINTR);
  errno = saved_errno;
}

static int
install_sigwinch(void) {
  if (pipe(sigwinch_pipe) < 0) {
    return -1;
  }
  for (int i = 0; i < 2; i++) {
    int flags = fcntl(sigwinch_pipe[i], F_GETFL, 0);
    if (flags >= 0) {
      fcntl(sigwinch_pipe[i], F_SETFL, flags | O_NONBLOCK);
    }
    fcntl(sigwinch_pipe[i], F_SETFD, FD_CLOEXEC);
  }
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  action.sa_handler = sigwinch_handler;
  return sigaction(SIGWINCH, &action, NULL);
}

static void
drain_sigwinch_pipe(void) {
  uint8_t buffer[64];
  for (;;) {
    ssize_t n = read(sigwinch_pipe[0], buffer, sizeof(buffer));
    if (n > 0) {
      continue;
    }
    if (n < 0 && errno == EINTR) {
      continue;
    }
    return;
  }
}

static int
current_winsize(int32_t *rows, int32_t *cols) {
  /* Prefer stdout, then stdin, then stderr: any of them may be redirected
   * individually while the others still point at the terminal. */
  if (op_winsize(1, rows, cols) == 0) {
    return 0;
  }
  if (op_winsize(0, rows, cols) == 0) {
    return 0;
  }
  return op_winsize(2, rows, cols);
}

/* Resize events are coalesced through a one-frame output buffer on the
 * non-blocking event socket: while the parent is not draining, only the
 * pending flag advances, and the frame is (re)built with the latest size
 * when the socket accepts it. */
static uint8_t event_outbuf[7 + 9];
static size_t event_out_pos = 0;
static size_t event_out_len = 0;
static int resize_pending = 0;

static void
pump_resize_events(void) {
  for (;;) {
    if (event_out_len > 0) {
      ssize_t n = send(
        event_sock, event_outbuf + event_out_pos,
        event_out_len - event_out_pos, 0
      );
      if (n < 0) {
        if (errno == EINTR) {
          continue;
        }
        /* EAGAIN: wait for POLLOUT. Other errors: the parent is gone; the
         * control connection will report it. */
        return;
      }
      event_out_pos += (size_t)n;
      if (event_out_pos < event_out_len) {
        continue;
      }
      event_out_pos = 0;
      event_out_len = 0;
    }
    if (!resize_pending) {
      return;
    }
    int32_t rows;
    int32_t cols;
    resize_pending = 0;
    if (current_winsize(&rows, &cols) < 0) {
      return;
    }
    fill_frame_header(event_outbuf, KIND_EVENT, 0, 9);
    event_outbuf[7] = EVENT_RESIZE;
    put_u32(event_outbuf + 8, (uint32_t)rows);
    put_u32(event_outbuf + 12, (uint32_t)cols);
    event_out_len = sizeof(event_outbuf);
  }
}

#endif /* _WIN32 */

/* ---------- request handling ---------- */

static void
restore_original_state(void) {
  if (state_dirty && has_original_state) {
    (void)op_set_state(
      original_input_slot, original_output_slot, &original_state
    );
    state_dirty = 0;
  }
}

/* Returns 0 to continue, 1 on clean shutdown, -1 on disconnect/protocol
 * violation. */
static int
handle_request(void) {
  uint8_t header[7];
  if (recv_all(control_sock, header, sizeof(header)) < 0) {
    return -1;
  }
  uint8_t op = header[0];
  uint32_t req_id = get_u32(header + 1);
  uint16_t len = get_u16(header + 5);
  uint8_t payload[MAX_PAYLOAD];
  if (len > MAX_PAYLOAD) {
    return -1;
  }
  if (len > 0 && recv_all(control_sock, payload, len) < 0) {
    return -1;
  }

  switch (op) {
    case OP_ISATTY: {
      if (len != 1 || payload[0] > 2) {
        return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
      }
      int is_tty = 0;
      if (op_isatty(payload[0], &is_tty) < 0) {
        return send_err(req_id, last_error()) < 0 ? -1 : 0;
      }
      uint8_t result = (uint8_t)(is_tty ? 1 : 0);
      return send_ok(req_id, &result, 1) < 0 ? -1 : 0;
    }
    case OP_ENTER_RAW: {
      if (len != 2 || payload[0] > 2 || payload[1] > 2) {
        return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
      }
      tty_state_t current;
      memset(&current, 0, sizeof(current));
      if (op_get_state(payload[0], payload[1], &current) < 0) {
        return send_err(req_id, last_error()) < 0 ? -1 : 0;
      }
      if (!has_original_state) {
        original_state = current;
        original_input_slot = payload[0];
        original_output_slot = payload[1];
        has_original_state = 1;
      }
      tty_state_t raw;
      memset(&raw, 0, sizeof(raw));
      op_make_raw(&current, &raw);
      if (op_set_state(payload[0], payload[1], &raw) < 0) {
        return send_err(req_id, last_error()) < 0 ? -1 : 0;
      }
      state_dirty = 1;
      return send_ok(req_id, NULL, 0) < 0 ? -1 : 0;
    }
    case OP_LEAVE_RAW: {
      if (len != 2 || payload[0] > 2 || payload[1] > 2) {
        return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
      }
      if (state_dirty && has_original_state) {
        if (op_set_state(payload[0], payload[1], &original_state) < 0) {
          return send_err(req_id, last_error()) < 0 ? -1 : 0;
        }
        state_dirty = 0;
      }
      return send_ok(req_id, NULL, 0) < 0 ? -1 : 0;
    }
    case OP_WINSIZE: {
      if (len != 1 || payload[0] > 2) {
        return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
      }
      int32_t rows;
      int32_t cols;
      if (op_winsize(payload[0], &rows, &cols) < 0) {
        return send_err(req_id, last_error()) < 0 ? -1 : 0;
      }
      uint8_t result[8];
      put_u32(result, (uint32_t)rows);
      put_u32(result + 4, (uint32_t)cols);
      return send_ok(req_id, result, sizeof(result)) < 0 ? -1 : 0;
    }
    case OP_WATCH: {
      if (len != 1) {
        return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
      }
      watch_enabled = payload[0] != 0;
#ifdef _WIN32
      /* Streaming cannot be un-started without losing buffered records;
       * disabling merely stops a not-yet-started stream. */
      if (watch_enabled) {
        start_watching();
      }
#else
      if (!watch_enabled) {
        resize_pending = 0;
      }
#endif
      return send_ok(req_id, NULL, 0) < 0 ? -1 : 0;
    }
    case OP_SHUTDOWN: {
      (void)send_ok(req_id, NULL, 0);
      return 1;
    }
    default:
      set_error(PROTO_EINVAL);
      return send_err(req_id, PROTO_EINVAL) < 0 ? -1 : 0;
  }
}

/* ---------- connection setup ---------- */

static socket_t
connect_to_parent(uint16_t port) {
  socket_t sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock == INVALID_SOCKET_VALUE) {
    return INVALID_SOCKET_VALUE;
  }
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
#ifdef _WIN32
    closesocket(sock);
#else
    close(sock);
#endif
    return INVALID_SOCKET_VALUE;
  }
  int one = 1;
  setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (const char *)&one, sizeof(one));
  return sock;
}

static int
send_handshake(socket_t sock, uint32_t magic, const char *token) {
  size_t token_len = strlen(token);
  uint8_t header[8];
  put_u32(header, magic);
  put_u16(header + 4, PROTO_VERSION);
  put_u16(header + 6, (uint16_t)token_len);
  if (send_all(sock, header, sizeof(header)) < 0) {
    return -1;
  }
  return send_all(sock, (const uint8_t *)token, token_len);
}

/* ---------- main loop ---------- */

#ifdef _WIN32

static int
serve(void) {
  for (;;) {
    int rc = handle_request();
    if (rc != 0) {
      return rc;
    }
  }
}

#else /* !_WIN32 */

static int
serve(void) {
  for (;;) {
    pump_resize_events();
    struct pollfd fds[3];
    fds[0].fd = control_sock;
    fds[0].events = POLLIN;
    fds[0].revents = 0;
    fds[1].fd = sigwinch_pipe[0];
    fds[1].events = POLLIN;
    fds[1].revents = 0;
    nfds_t nfds = 2;
    if (event_out_len > 0) {
      fds[2].fd = event_sock;
      fds[2].events = POLLOUT;
      fds[2].revents = 0;
      nfds = 3;
    }
    int ready = poll(fds, nfds, -1);
    if (ready < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -1;
    }
    if (fds[1].revents & POLLIN) {
      drain_sigwinch_pipe();
      if (watch_enabled) {
        resize_pending = 1;
      }
    }
    if (fds[0].revents & (POLLIN | POLLHUP | POLLERR)) {
      int rc = handle_request();
      if (rc != 0) {
        return rc;
      }
    }
  }
}

#endif /* _WIN32 */

int
main(int argc, char **argv) {
  long port = 0;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
      port = strtol(argv[i + 1], NULL, 10);
      i++;
    } else if (strcmp(argv[i], "--version") == 0) {
      printf("tty-sidecar protocol %d\n", PROTO_VERSION);
      return 0;
    }
  }
  if (port <= 0 || port > 65535) {
    fprintf(stderr, "tty-sidecar: usage: tty-sidecar --port <port>\n");
    return 2;
  }
  const char *token = getenv("MOONBIT_TTY_SIDECAR_TOKEN");
  if (token == NULL || token[0] == '\0' || strlen(token) > MAX_TOKEN) {
    fprintf(stderr, "tty-sidecar: MOONBIT_TTY_SIDECAR_TOKEN is not set\n");
    return 2;
  }

#ifdef _WIN32
  WSADATA wsa_data;
  if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
    return 3;
  }
#else
  signal(SIGPIPE, SIG_IGN);
  if (install_sigwinch() < 0) {
    return 3;
  }
#endif

  control_sock = connect_to_parent((uint16_t)port);
  if (control_sock == INVALID_SOCKET_VALUE) {
    return 3;
  }
  /* Complete the control handshake before opening the event connection so
   * the parent can identify the two connections by accept order. */
  if (send_handshake(control_sock, MAGIC_CONTROL, token) < 0) {
    return 4;
  }
  event_sock = connect_to_parent((uint16_t)port);
  if (event_sock == INVALID_SOCKET_VALUE) {
    return 3;
  }
  if (send_handshake(event_sock, MAGIC_EVENT, token) < 0) {
    return 4;
  }
#ifndef _WIN32
  int event_flags = fcntl(event_sock, F_GETFL, 0);
  if (event_flags >= 0) {
    fcntl(event_sock, F_SETFL, event_flags | O_NONBLOCK);
  }
#endif

  int rc = serve();
  restore_original_state();
  return rc < 0 ? 5 : 0;
}
