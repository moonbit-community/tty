#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <termios.h>
#endif

typedef struct moonbit_tty_state {
#ifdef _WIN32
  DWORD mode;
#else
  struct termios termios;
#endif
} moonbit_tty_state_t;

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_get_sizeof_state(void) {
  return (int32_t)sizeof(moonbit_tty_state_t);
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_get_state(
#ifdef _WIN32
  HANDLE fd,
#else
  int32_t fd,
#endif
  moonbit_tty_state_t *state
) {
#ifdef _WIN32
  if (state == NULL) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }
  if (!GetConsoleMode(fd, &state->mode)) {
    return -1;
  }
  return 0;
#else
  if (state == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (tcgetattr((int)fd, &state->termios) < 0) {
    return -1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_set_state(
#ifdef _WIN32
  HANDLE fd,
#else
  int32_t fd,
#endif
  moonbit_tty_state_t *state
) {
#ifdef _WIN32
  if (state == NULL) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }
  if (!SetConsoleMode(fd, state->mode)) {
    return -1;
  }
  return 0;
#else
  if (state == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (tcsetattr((int)fd, TCSANOW, &state->termios) < 0) {
    return -1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT
void
moonbit_tty_make_raw_state(
  moonbit_tty_state_t *state,
  moonbit_tty_state_t *raw
) {
  if (state == NULL || raw == NULL) {
    return;
  }
  *raw = *state;
#ifdef _WIN32
  DWORD mode = state->mode;
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
  raw->mode = mode;
#else
  raw->termios.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP |
                            INLCR | IGNCR | ICRNL | IXON);
  raw->termios.c_oflag &= ~OPOST;
  raw->termios.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  raw->termios.c_cflag &= ~(CSIZE | PARENB);
  raw->termios.c_cflag |= CS8;
  raw->termios.c_cc[VMIN] = 1;
  raw->termios.c_cc[VTIME] = 0;
#endif
}
