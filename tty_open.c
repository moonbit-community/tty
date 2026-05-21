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
