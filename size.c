#include <stdint.h>
#include <moonbit.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#include <sys/ioctl.h>
#endif

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_get_window_size(
#ifdef _WIN32
  HANDLE fd,
#else
  int32_t fd,
#endif
  int32_t *rows,
  int32_t *cols
) {
  if (rows == NULL || cols == NULL) {
#ifdef _WIN32
    SetLastError(ERROR_INVALID_PARAMETER);
#else
    errno = EINVAL;
#endif
    return -1;
  }

#ifdef _WIN32
  CONSOLE_SCREEN_BUFFER_INFO info;
  if (!GetConsoleScreenBufferInfo(fd, &info)) {
    return -1;
  }
  int32_t height = (int32_t)(info.srWindow.Bottom - info.srWindow.Top + 1);
  int32_t width = (int32_t)(info.srWindow.Right - info.srWindow.Left + 1);
#else
  struct winsize size;
  if (ioctl((int)fd, TIOCGWINSZ, &size) < 0) {
    return -1;
  }
  int32_t height = (int32_t)size.ws_row;
  int32_t width = (int32_t)size.ws_col;
#endif

  if (height <= 0 || width <= 0) {
#ifdef _WIN32
    SetLastError(ERROR_INVALID_PARAMETER);
#else
    errno = EINVAL;
#endif
    return -1;
  }

  *rows = height;
  *cols = width;
  return 0;
}
