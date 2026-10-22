// tty sidecar for Unix: owns /dev/tty on behalf of the program that spawned
// it and relays everything over its stdio pipes. Single threaded. The frame
// protocol is described in README.md next to this file.
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>

enum {
  TAG_SET_RAW = 0x01, TAG_WRITE = 0x02,
  TAG_HELLO = 0x80, TAG_INPUT = 0x81, TAG_RESIZE = 0x82, TAG_ERROR = 0x83,
};
#define PROTOCOL_VERSION 1u
// HELLO `kind`: the input side is a byte stream (VT sequences).
#define INPUT_KIND_BYTES 0

static volatile sig_atomic_t got_winch = 0;
static volatile sig_atomic_t got_quit = 0;
static void on_winch(int s) { (void)s; got_winch = 1; }
static void on_quit(int s) { (void)s; got_quit = 1; }

static int tty_fd = -1;
static struct termios saved;
static int is_raw = 0;

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

static int send_frame(uint8_t tag, const void *payload, uint32_t len) {
  uint8_t hdr[5] = { tag, len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, (len >> 24) & 0xff };
  if (write_all(1, hdr, sizeof hdr) < 0) return -1;
  return len ? write_all(1, payload, len) : 0;
}

static void put_u16(uint8_t *p, unsigned v) { p[0] = v & 0xff; p[1] = (v >> 8) & 0xff; }

static int send_error(const char *msg) { return send_frame(TAG_ERROR, msg, (uint32_t)strlen(msg)); }

static int send_hello(void) {
  struct winsize ws = {0};
  ioctl(tty_fd, TIOCGWINSZ, &ws);
  uint8_t p[9] = { PROTOCOL_VERSION, 0, 0, 0 };
  put_u16(p + 4, ws.ws_row);
  put_u16(p + 6, ws.ws_col);
  p[8] = INPUT_KIND_BYTES;
  return send_frame(TAG_HELLO, p, sizeof p);
}

static int send_resize(void) {
  struct winsize ws;
  if (ioctl(tty_fd, TIOCGWINSZ, &ws) < 0) return 0;
  uint8_t p[4];
  put_u16(p, ws.ws_row);
  put_u16(p + 2, ws.ws_col);
  return send_frame(TAG_RESIZE, p, sizeof p);
}

static void restore(void) {
  if (is_raw) {
    tcsetattr(tty_fd, TCSANOW, &saved);
    is_raw = 0;
  }
}

static int set_raw(int on) {
  if (!on) { restore(); return 0; }
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

static uint8_t cmd_buf[1 << 16];
static size_t cmd_len = 0;

// Returns -1 when the parent asked for something we must stop on.
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
        if (set_raw(len > 0 && payload[0]) < 0 && send_error(strerror(errno)) < 0) return -1;
        break;
      case TAG_WRITE:
        if (write_all(tty_fd, payload, len) < 0 && send_error(strerror(errno)) < 0) return -1;
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

int main(void) {
  tty_fd = open("/dev/tty", O_RDWR | O_NOCTTY | O_CLOEXEC);
  if (tty_fd < 0) { send_error(strerror(errno)); return 1; }
  signal(SIGPIPE, SIG_IGN);

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

  if (send_hello() < 0) return 1;

  uint8_t tty_buf[4096];
  int maxfd = tty_fd > 0 ? tty_fd : 0;
  for (;;) {
    if (got_quit) break;
    if (got_winch) {
      got_winch = 0;
      if (send_resize() < 0) break;
    }
    fd_set r;
    FD_ZERO(&r);
    FD_SET(0, &r);
    FD_SET(tty_fd, &r);
    int n = pselect(maxfd + 1, &r, NULL, NULL, NULL, &in_select);
    if (n < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (FD_ISSET(tty_fd, &r)) {
      ssize_t k = read(tty_fd, tty_buf, sizeof tty_buf);
      if (k < 0) {
        if (errno != EINTR && errno != EAGAIN) break;
      } else if (k == 0) {
        break;  // terminal hung up
      } else if (send_frame(TAG_INPUT, tty_buf, (uint32_t)k) < 0) {
        break;  // parent gone
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
