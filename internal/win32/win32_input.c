#include <moonbit.h>
#include <stdint.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <errno.h>
#endif

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_get_sizeof_input_record(void) {
#ifdef _WIN32
  return (int32_t)sizeof(INPUT_RECORD);
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_read_console_input_record(
#ifdef _WIN32
  HANDLE fd,
#else
  intptr_t fd,
#endif
  void *output_record
) {
  if (output_record == NULL) {
#ifdef _WIN32
    SetLastError(ERROR_INVALID_PARAMETER);
#else
    errno = EINVAL;
#endif
    return -1;
  }

#ifdef _WIN32
  memset(output_record, 0, sizeof(INPUT_RECORD));

  INPUT_RECORD record;
  DWORD count = 0;
  if (!PeekConsoleInputW(fd, &record, 1, &count)) {
    return -1;
  }
  if (count == 0) {
    return 0;
  }
  if (!ReadConsoleInputW(fd, &record, 1, &count)) {
    return -1;
  }
  if (count == 0) {
    return 0;
  }

  memcpy(output_record, &record, sizeof(INPUT_RECORD));
  return 1;
#else
  (void)fd;
  (void)output_record;
  errno = ENOSYS;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_console_input_vt_enabled(
#ifdef _WIN32
  HANDLE fd
#else
  intptr_t fd
#endif
) {
#ifdef _WIN32
  DWORD mode = 0;
  if (!GetConsoleMode(fd, &mode)) {
    return -1;
  }
#ifdef ENABLE_VIRTUAL_TERMINAL_INPUT
  return (mode & ENABLE_VIRTUAL_TERMINAL_INPUT) != 0 ? 1 : 0;
#else
  return 0;
#endif
#else
  (void)fd;
  errno = ENOSYS;
  return -1;
#endif
}
