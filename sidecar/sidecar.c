// tty sidecar: owns the terminal on behalf of the program that spawned it
// and relays everything over its stdio pipes. The frame protocol is
// described in README.md next to this file; the MoonBit side is
// `internal/sidecar`.
//
// The first part is the protocol, shared by both platforms. Then comes the
// Windows half (console handles, a thread blocking in ReadConsoleInputW that
// forwards raw INPUT_RECORDs, a second thread reading commands) and the Unix
// half (/dev/tty, termios, single-threaded pselect over the command pipe, the
// terminal and the event pipe, SIGWINCH through a handler, input forwarded as
// VT bytes). Event frames are queued and written as the pipe accepts them, so
// a parent that is slow to read events never stops command processing; the
// terminal is simply not read while the queue is large.
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>
#endif

enum {
  TAG_SET_RAW = 0x01, TAG_WRITE = 0x02,
  TAG_HELLO = 0x80, TAG_INPUT = 0x81, TAG_RESIZE = 0x82, TAG_ERROR = 0x83,
  TAG_RECORD = 0x84,
};
#define PROTOCOL_VERSION 1u

// ===== protocol, on top of the platform primitives declared here =====

// Write everything or fail. `write_out` goes to the parent, `write_terminal`
// to the terminal.
static int write_out(const void *p, size_t n);
static int write_terminal(const void *p, size_t n);
static int set_raw(int on);
static int window_size(unsigned *rows, unsigned *cols);
// Report the last OS error of `what` to the parent.
static int report_failure(const char *what);
// Frames may be sent from more than one thread on Windows.
static void out_lock(void);
static void out_unlock(void);

static void put_u16(uint8_t *p, unsigned v) { p[0] = v & 0xff; p[1] = (v >> 8) & 0xff; }

static int send_frame(uint8_t tag, const void *payload, uint32_t len) {
  uint8_t hdr[5] = { tag, len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, (len >> 24) & 0xff };
  out_lock();
  int rc = write_out(hdr, sizeof hdr);
  if (rc == 0 && len) rc = write_out(payload, len);
  out_unlock();
  return rc;
}

static int send_error(const char *msg) { return send_frame(TAG_ERROR, msg, (uint32_t)strlen(msg)); }

static int send_hello(void) {
  unsigned rows = 0, cols = 0;
  window_size(&rows, &cols);
  uint8_t p[8] = { PROTOCOL_VERSION, 0, 0, 0 };
  put_u16(p + 4, rows);
  put_u16(p + 6, cols);
  return send_frame(TAG_HELLO, p, sizeof p);
}

static int send_resize(void) {
  unsigned rows, cols;
  if (window_size(&rows, &cols) < 0) return 0;
  uint8_t p[4];
  put_u16(p, rows);
  put_u16(p + 2, cols);
  return send_frame(TAG_RESIZE, p, sizeof p);
}

static uint8_t cmd_buf[1 << 16];
static size_t cmd_len = 0;

// Apply every complete command in `cmd_buf`. Returns -1 when the sidecar
// must stop (a protocol error, or the parent can no longer be reached).
static int handle_commands(void) {
  size_t off = 0;
  while (cmd_len - off >= 5) {
    uint8_t tag = cmd_buf[off];
    uint32_t len = (uint32_t)cmd_buf[off + 1] | (uint32_t)cmd_buf[off + 2] << 8 |
                   (uint32_t)cmd_buf[off + 3] << 16 | (uint32_t)cmd_buf[off + 4] << 24;
    if (len > sizeof cmd_buf - 5) { send_error("command frame too large"); return -1; }
    if (cmd_len - off - 5 < len) break;
    const uint8_t *payload = cmd_buf + off + 5;
    switch (tag) {
      case TAG_SET_RAW:
        if (len != 1) { send_error("malformed SET_RAW command"); return -1; }
        if (set_raw(payload[0] != 0) < 0 && report_failure("set raw mode") < 0) return -1;
        break;
      case TAG_WRITE:
        if (write_terminal(payload, len) < 0 && report_failure("write to terminal") < 0) return -1;
        break;
      default:
        send_error("unknown command");
        return -1;
    }
    off += 5 + len;
  }
  memmove(cmd_buf, cmd_buf + off, cmd_len - off);
  cmd_len -= off;
  return 0;
}

#ifdef _WIN32
// ===== Windows =====

static HANDLE in_pipe, out_pipe, conin, conout;
static CRITICAL_SECTION out_cs;
// Console mode state is touched by the command thread, the record thread
// and the console control handler, hence its own lock.
static CRITICAL_SECTION mode_cs;
static DWORD saved_in_mode, saved_out_mode;
static int is_raw = 0;

static void out_lock(void) { EnterCriticalSection(&out_cs); }
static void out_unlock(void) { LeaveCriticalSection(&out_cs); }

static int write_all(HANDLE h, const void *p, size_t n) {
  const uint8_t *c = p;
  while (n > 0) {
    DWORD w = 0;
    if (!WriteFile(h, c, (DWORD)n, &w, NULL)) return -1;
    c += w;
    n -= w;
  }
  return 0;
}

static int write_out(const void *p, size_t n) { return write_all(out_pipe, p, n); }
static int write_terminal(const void *p, size_t n) { return write_all(conout, p, n); }

static int report_failure(const char *what) {
  char msg[256];
  snprintf(msg, sizeof msg, "%s failed with error %lu", what, (unsigned long)GetLastError());
  return send_error(msg);
}

static int window_size(unsigned *rows, unsigned *cols) {
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(conout, &info)) return -1;
  *rows = (unsigned)(info.srWindow.Bottom - info.srWindow.Top + 1);
  *cols = (unsigned)(info.srWindow.Right - info.srWindow.Left + 1);
  return 0;
}

// Put both console modes back; `is_raw` is cleared only once both are.
static int restore_locked(void) {
  if (!is_raw) return 0;
  int ok = SetConsoleMode(conin, saved_in_mode);
  ok = SetConsoleMode(conout, saved_out_mode) && ok;
  if (ok) is_raw = 0;
  return ok ? 0 : -1;
}

static int restore(void) {
  EnterCriticalSection(&mode_cs);
  int rc = restore_locked();
  LeaveCriticalSection(&mode_cs);
  return rc;
}

// No echo, no line buffering, no Ctrl-C processing, VT input and output,
// window size events. Either both modes change or neither does.
static int set_raw(int on) {
  if (!on) return restore();
  EnterCriticalSection(&mode_cs);
  int rc = 0;
  if (!is_raw) {
    rc = -1;
    if (GetConsoleMode(conin, &saved_in_mode) && GetConsoleMode(conout, &saved_out_mode)) {
      DWORD in = saved_in_mode;
      in &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT);
      in |= ENABLE_EXTENDED_FLAGS;
      in &= ~ENABLE_QUICK_EDIT_MODE;
      in |= ENABLE_VIRTUAL_TERMINAL_INPUT;
      in |= ENABLE_WINDOW_INPUT;
      DWORD out = saved_out_mode;
      out |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN;
      if (SetConsoleMode(conin, in)) {
        if (SetConsoleMode(conout, out)) {
          is_raw = 1;
          rc = 0;
        } else {
          DWORD error = GetLastError();
          SetConsoleMode(conin, saved_in_mode);
          SetLastError(error);
        }
      }
    }
  }
  LeaveCriticalSection(&mode_cs);
  return rc;
}

// Commands arrive on the stdin pipe; EOF there means the parent is gone.
static DWORD WINAPI command_thread(LPVOID arg) {
  (void)arg;
  for (;;) {
    if (cmd_len == sizeof cmd_buf) { send_error("command frame too large"); break; }
    DWORD k = 0;
    if (!ReadFile(in_pipe, cmd_buf + cmd_len, (DWORD)(sizeof cmd_buf - cmd_len), &k, NULL) || k == 0) break;
    cmd_len += k;
    if (handle_commands() < 0) break;
  }
  restore();
  ExitProcess(0);
  return 0;
}

// Ctrl-C and Ctrl-Break are the parent's business; in raw mode they arrive
// as key records anyway. Closing the console window restores it.
static BOOL WINAPI ctrl_handler(DWORD type) {
  if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT) return TRUE;
  restore();
  return FALSE;
}

int main(void) {
  in_pipe = GetStdHandle(STD_INPUT_HANDLE);
  out_pipe = GetStdHandle(STD_OUTPUT_HANDLE);
  InitializeCriticalSection(&out_cs);
  InitializeCriticalSection(&mode_cs);
  conin = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                      NULL, OPEN_EXISTING, 0, NULL);
  if (conin == INVALID_HANDLE_VALUE) { report_failure("CreateFileW(CONIN$)"); return 1; }
  conout = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                       NULL, OPEN_EXISTING, 0, NULL);
  if (conout == INVALID_HANDLE_VALUE) { report_failure("CreateFileW(CONOUT$)"); return 1; }
  SetConsoleCtrlHandler(ctrl_handler, TRUE);
  if (send_hello() < 0) return 1;
  if (CreateThread(NULL, 0, command_thread, NULL, 0, NULL) == NULL) {
    report_failure("CreateThread");
    return 1;
  }
  for (;;) {
    INPUT_RECORD record;
    DWORD n = 0;
    if (!ReadConsoleInputW(conin, &record, 1, &n)) break;
    if (n == 0) continue;
    int rc = record.EventType == WINDOW_BUFFER_SIZE_EVENT
      ? send_resize()
      : send_frame(TAG_RECORD, &record, (uint32_t)sizeof record);
    if (rc < 0) break;  // parent gone
  }
  restore();
  return 0;
}

#else
// ===== Unix =====

static volatile sig_atomic_t got_winch = 0;
static volatile sig_atomic_t got_quit = 0;
static void on_winch(int s) { (void)s; got_winch = 1; }
static void on_quit(int s) { (void)s; got_quit = 1; }

static int tty_fd = -1;
static struct termios saved;
static int is_raw = 0;

// Single threaded: nothing to lock.
static void out_lock(void) {}
static void out_unlock(void) {}

// Event frames waiting for the parent to read them. Above the high-water
// mark the terminal is left unread, which is the backpressure.
static uint8_t *out_buf = NULL;
static size_t out_len = 0, out_cap = 0;
#define OUT_HIGH_WATER (1u << 20)
// Set once the parent stopped reading events; commands are still run until
// the command pipe closes, so no write that the parent already issued is lost.
static int events_dead = 0;

static int write_all(int fd, const void *p, size_t n) {
  const uint8_t *c = p;
  while (n > 0) {
    ssize_t w = write(fd, c, n);
    if (w < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    c += w;
    n -= (size_t)w;
  }
  return 0;
}

static int write_out(const void *p, size_t n) {
  if (events_dead) return 0;
  if (out_len + n > out_cap) {
    size_t cap = out_cap ? out_cap : 65536;
    while (cap < out_len + n) cap *= 2;
    uint8_t *grown = realloc(out_buf, cap);
    if (grown == NULL) return -1;
    out_buf = grown;
    out_cap = cap;
  }
  memcpy(out_buf + out_len, p, n);
  out_len += n;
  return 0;
}

// Write as much of the queue as the pipe takes right now; -1 once the
// parent is gone.
static int flush_out(void) {
  while (out_len > 0) {
    ssize_t w = write(1, out_buf, out_len);
    if (w < 0) {
      if (errno == EINTR) continue;
      if (errno == EAGAIN || errno == EWOULDBLOCK) return 0;
      return -1;
    }
    memmove(out_buf, out_buf + w, out_len - (size_t)w);
    out_len -= (size_t)w;
  }
  return 0;
}

static int write_terminal(const void *p, size_t n) { return write_all(tty_fd, p, n); }

static int report_failure(const char *what) {
  char msg[256];
  snprintf(msg, sizeof msg, "%s failed: %s", what, strerror(errno));
  return send_error(msg);
}

static int window_size(unsigned *rows, unsigned *cols) {
  struct winsize ws;
  if (ioctl(tty_fd, TIOCGWINSZ, &ws) < 0) return -1;
  *rows = ws.ws_row;
  *cols = ws.ws_col;
  return 0;
}

static int restore(void) {
  if (!is_raw) return 0;
  int rc;
  do {
    rc = tcsetattr(tty_fd, TCSANOW, &saved);
  } while (rc < 0 && errno == EINTR);
  if (rc == 0) is_raw = 0;
  return rc;
}

static int set_raw(int on) {
  if (!on) return restore();
  if (is_raw) return 0;
  struct termios t;
  if (tcgetattr(tty_fd, &t) < 0) return -1;
  saved = t;
  cfmakeraw(&t);
  t.c_cc[VMIN] = 1;
  t.c_cc[VTIME] = 0;
  if (tcsetattr(tty_fd, TCSANOW, &t) < 0) return -1;
  is_raw = 1;
  return 0;
}

int main(void) {
  tty_fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC);
  // Frames are only queued until the main loop flushes them, and stdout is
  // still blocking here, so flush the error before exiting.
  if (tty_fd < 0) { report_failure("open /dev/tty"); flush_out(); return 1; }
  signal(SIGPIPE, SIG_IGN);
  // Restoring the terminal from a background process group (the shell took
  // the foreground back after the parent died) must not stop us.
  signal(SIGTTOU, SIG_IGN);

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = on_winch;
  sigaction(SIGWINCH, &sa, NULL);
  sa.sa_handler = on_quit;
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);
  sigaction(SIGINT, &sa, NULL);

  // Keep the handled signals blocked except inside pselect, so a signal can
  // never slip in between checking the flags and going to sleep.
  sigset_t handled, in_select;
  sigemptyset(&handled);
  sigaddset(&handled, SIGWINCH);
  sigaddset(&handled, SIGTERM);
  sigaddset(&handled, SIGHUP);
  sigaddset(&handled, SIGINT);
  sigprocmask(SIG_BLOCK, &handled, &in_select);
  sigdelset(&in_select, SIGWINCH);
  sigdelset(&in_select, SIGTERM);
  sigdelset(&in_select, SIGHUP);
  sigdelset(&in_select, SIGINT);

  fcntl(1, F_SETFL, fcntl(1, F_GETFL) | O_NONBLOCK);
  if (send_hello() < 0) return 1;

  uint8_t tty_buf[4096];
  int maxfd = tty_fd > 1 ? tty_fd : 1;
  for (;;) {
    if (got_quit) break;
    if (got_winch) {
      got_winch = 0;
      if (send_resize() < 0) break;
    }
    fd_set r, w;
    FD_ZERO(&r);
    FD_ZERO(&w);
    FD_SET(0, &r);
    if (!events_dead && out_len < OUT_HIGH_WATER) FD_SET(tty_fd, &r);
    if (out_len > 0) FD_SET(1, &w);
    int n = pselect(maxfd + 1, &r, &w, NULL, NULL, &in_select);
    if (n < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (FD_ISSET(1, &w) && flush_out() < 0) {
      events_dead = 1;  // parent stopped reading; keep running its commands
      out_len = 0;
    }
    if (FD_ISSET(tty_fd, &r)) {
      ssize_t k = read(tty_fd, tty_buf, sizeof tty_buf);
      if (k < 0) {
        if (errno != EINTR && errno != EAGAIN) break;
      } else if (k == 0) {
        break;  // terminal hung up
      } else if (send_frame(TAG_INPUT, tty_buf, (uint32_t)k) < 0) {
        break;  // out of memory
      }
    }
    if (FD_ISSET(0, &r)) {
      if (cmd_len == sizeof cmd_buf) { send_error("command frame too large"); break; }
      ssize_t k = read(0, cmd_buf + cmd_len, sizeof cmd_buf - cmd_len);
      if (k < 0) {
        if (errno == EINTR) continue;
        break;
      }
      if (k == 0) break;  // parent closed the command pipe
      cmd_len += (size_t)k;
      if (handle_commands() < 0) break;
    }
  }
  restore();
  return 0;
}
#endif
