#include <moonbit.h>
#include <stdint.h>

#ifndef _WIN32
#include <fcntl.h>
#include <unistd.h>

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_open_controlling_terminal(void) {
#ifdef O_CLOEXEC
  return (int32_t)open("/dev/tty", O_RDWR | O_CLOEXEC);
#else
  int fd = open("/dev/tty", O_RDWR);
  if (fd >= 0) {
    fcntl(fd, F_SETFD, FD_CLOEXEC);
  }
  return (int32_t)fd;
#endif
}
#endif

#ifdef _WIN32
#include <windows.h>

// `CONIN$` / `CONOUT$` are console (character) devices, not filesystem files.
// They are opened directly here as synchronous (non-overlapped) handles so they
// can be wrapped with `@async/raw_fd.RawFdStream`, which classifies them by
// `GetFileType` (CharDevice). Going through `@async/fs.open` instead would probe
// the handle with `GetFileInformationByHandle`, which fails on console devices.
static HANDLE
moonbit_tty_open_console(const wchar_t *name) {
  return CreateFileW(
    name,
    GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    0, // no FILE_FLAG_OVERLAPPED: RawFdStream requires a non-overlapped handle
    NULL
  );
}

MOONBIT_FFI_EXPORT
HANDLE
moonbit_tty_open_console_input(void) {
  return moonbit_tty_open_console(L"CONIN$");
}

MOONBIT_FFI_EXPORT
HANDLE
moonbit_tty_open_console_output(void) {
  return moonbit_tty_open_console(L"CONOUT$");
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_handle_is_valid(HANDLE fd) {
  return (fd != INVALID_HANDLE_VALUE && fd != NULL) ? 1 : 0;
}
#endif
