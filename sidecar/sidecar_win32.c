// tty sidecar for Windows: owns the console on behalf of the program that
// spawned it and relays everything over its stdio pipes. The frame protocol
// is described in README.md next to this file; the input side is a stream of
// raw INPUT_RECORDs (HELLO kind 1), decoded by `internal/win32` in MoonBit.
//
// One thread blocks in ReadConsoleInputW and forwards records, another reads
// commands from stdin.
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum {
  TAG_SET_RAW = 0x01, TAG_WRITE = 0x02,
  TAG_HELLO = 0x80, TAG_INPUT = 0x81, TAG_RESIZE = 0x82, TAG_ERROR = 0x83,
  TAG_RECORD = 0x84,
};
#define PROTOCOL_VERSION 1u
// HELLO `kind`: the input side is a stream of INPUT_RECORDs.
#define INPUT_KIND_RECORDS 1

static HANDLE in_pipe, out_pipe, conin, conout;
static CRITICAL_SECTION out_lock;
static DWORD saved_in_mode, saved_out_mode;
static int have_out_mode = 0;
static int is_raw = 0;

static int write_all(HANDLE h, const void *p, DWORD n) {
  const uint8_t *c = p;
  while (n > 0) {
    DWORD w = 0;
    if (!WriteFile(h, c, n, &w, NULL)) return -1;
    c += w;
    n -= w;
  }
  return 0;
}

static int send_frame(uint8_t tag, const void *payload, uint32_t len) {
  uint8_t hdr[5] = { tag, len & 0xff, (len >> 8) & 0xff, (len >> 16) & 0xff, (len >> 24) & 0xff };
  EnterCriticalSection(&out_lock);
  int rc = write_all(out_pipe, hdr, sizeof hdr);
  if (rc == 0 && len) rc = write_all(out_pipe, payload, len);
  LeaveCriticalSection(&out_lock);
  return rc;
}

static void put_u16(uint8_t *p, unsigned v) { p[0] = v & 0xff; p[1] = (v >> 8) & 0xff; }

static int send_error(const char *msg) { return send_frame(TAG_ERROR, msg, (uint32_t)strlen(msg)); }

static int window_size(unsigned *rows, unsigned *cols) {
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(conout, &info)) return -1;
  *rows = (unsigned)(info.srWindow.Bottom - info.srWindow.Top + 1);
  *cols = (unsigned)(info.srWindow.Right - info.srWindow.Left + 1);
  return 0;
}

static int send_hello(void) {
  unsigned rows = 0, cols = 0;
  window_size(&rows, &cols);
  uint8_t p[9] = { PROTOCOL_VERSION, 0, 0, 0 };
  put_u16(p + 4, rows);
  put_u16(p + 6, cols);
  p[8] = INPUT_KIND_RECORDS;
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

static void restore(void) {
  if (!is_raw) return;
  SetConsoleMode(conin, saved_in_mode);
  if (have_out_mode) SetConsoleMode(conout, saved_out_mode);
  is_raw = 0;
}

// Same flags as the former state.c: no echo, no line buffering, no Ctrl-C
// processing, VT input and output, window size events.
static int set_raw(int on) {
  if (!on) { restore(); return 0; }
  if (is_raw) return 0;
  if (!GetConsoleMode(conin, &saved_in_mode)) return -1;
  DWORD mode = saved_in_mode;
  mode &= ~(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT);
  mode |= ENABLE_EXTENDED_FLAGS;
  mode &= ~ENABLE_QUICK_EDIT_MODE;
  mode |= ENABLE_VIRTUAL_TERMINAL_INPUT;
  mode |= ENABLE_WINDOW_INPUT;
  if (!SetConsoleMode(conin, mode)) return -1;
  have_out_mode = GetConsoleMode(conout, &saved_out_mode);
  if (have_out_mode) {
    DWORD out = saved_out_mode;
    out |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN;
    SetConsoleMode(conout, out);
  }
  is_raw = 1;
  return 0;
}

static void fail_last_error(const char *what) {
  char msg[256];
  DWORD code = GetLastError();
  snprintf(msg, sizeof msg, "%s failed with error %lu", what, (unsigned long)code);
  send_error(msg);
}

static uint8_t cmd_buf[1 << 16];
static size_t cmd_len = 0;

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
        if (set_raw(len > 0 && payload[0]) < 0) fail_last_error("SetConsoleMode");
        break;
      case TAG_WRITE:
        if (write_all(conout, payload, len) < 0) fail_last_error("WriteFile");
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
  InitializeCriticalSection(&out_lock);
  conin = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                      NULL, OPEN_EXISTING, 0, NULL);
  if (conin == INVALID_HANDLE_VALUE) { fail_last_error("CreateFileW(CONIN$)"); return 1; }
  conout = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                       NULL, OPEN_EXISTING, 0, NULL);
  if (conout == INVALID_HANDLE_VALUE) { fail_last_error("CreateFileW(CONOUT$)"); return 1; }
  SetConsoleCtrlHandler(ctrl_handler, TRUE);
  if (send_hello() < 0) return 1;
  HANDLE thread = CreateThread(NULL, 0, command_thread, NULL, 0, NULL);
  if (thread == NULL) { fail_last_error("CreateThread"); return 1; }
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
