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
  DWORD input_mode;
  DWORD output_mode;
  int32_t has_output_mode;
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
  HANDLE input_fd,
  HANDLE output_fd,
#else
  int32_t input_fd,
  int32_t output_fd,
#endif
  moonbit_tty_state_t *state
) {
#ifdef _WIN32
  if (state == NULL) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }
  if (!GetConsoleMode(input_fd, &state->input_mode)) {
    return -1;
  }
  state->output_mode = 0;
  state->has_output_mode = 0;
  if (GetConsoleMode(output_fd, &state->output_mode)) {
    state->has_output_mode = 1;
  }
  return 0;
#else
  (void)output_fd;
  if (state == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (tcgetattr((int)input_fd, &state->termios) < 0) {
    return -1;
  }
  return 0;
#endif
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_set_state(
#ifdef _WIN32
  HANDLE input_fd,
  HANDLE output_fd,
#else
  int32_t input_fd,
  int32_t output_fd,
#endif
  moonbit_tty_state_t *state
) {
#ifdef _WIN32
  if (state == NULL) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return -1;
  }
  if (!SetConsoleMode(input_fd, state->input_mode)) {
    return -1;
  }
  if (state->has_output_mode &&
      !SetConsoleMode(output_fd, state->output_mode)) {
    return -1;
  }
  return 0;
#else
  (void)output_fd;
  if (state == NULL) {
    errno = EINVAL;
    return -1;
  }
  if (tcsetattr((int)input_fd, TCSANOW, &state->termios) < 0) {
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
  DWORD mode = state->input_mode;
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
  raw->input_mode = mode;
  if (raw->has_output_mode) {
    DWORD output_mode = state->output_mode;
#ifdef ENABLE_PROCESSED_OUTPUT
    output_mode |= ENABLE_PROCESSED_OUTPUT;
#endif
#ifdef ENABLE_VIRTUAL_TERMINAL_PROCESSING
    output_mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
#endif
#ifdef DISABLE_NEWLINE_AUTO_RETURN
    output_mode |= DISABLE_NEWLINE_AUTO_RETURN;
#endif
    raw->output_mode = output_mode;
  }
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
