#include <moonbit.h>
#include <stdint.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_install_sigwinch_handler(intptr_t fd) {
  (void)fd;
  SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
  return -1;
}

MOONBIT_FFI_EXPORT
void
moonbit_tty_drain_sigwinch_pipe(intptr_t fd) {
  (void)fd;
}

#else

#include <errno.h>
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t moonbit_tty_sigwinch_fd = -1;
static struct sigaction moonbit_tty_previous_sigwinch_action;
static volatile sig_atomic_t moonbit_tty_has_previous_sigwinch_action = 0;

static void
moonbit_tty_dispatch_previous_sigwinch(
  int signo,
  siginfo_t *info,
  void *context
) {
  if (!moonbit_tty_has_previous_sigwinch_action) {
    return;
  }
  if (moonbit_tty_previous_sigwinch_action.sa_flags & SA_SIGINFO) {
    if (moonbit_tty_previous_sigwinch_action.sa_sigaction != NULL) {
      moonbit_tty_previous_sigwinch_action.sa_sigaction(signo, info, context);
    }
    return;
  }
  void (*handler)(int) = moonbit_tty_previous_sigwinch_action.sa_handler;
  if (handler != SIG_DFL && handler != SIG_IGN && handler != NULL) {
    handler(signo);
  }
}

static void
moonbit_tty_sigwinch_handler(int signo, siginfo_t *info, void *context) {
  int saved_errno = errno;
  int fd = (int)moonbit_tty_sigwinch_fd;
  if (fd >= 0) {
    unsigned char byte = 1;
    ssize_t rc;
    do {
      rc = write(fd, &byte, 1);
    } while (rc < 0 && errno == EINTR);
  }
  errno = saved_errno;
  moonbit_tty_dispatch_previous_sigwinch(signo, info, context);
}

MOONBIT_FFI_EXPORT
int32_t
moonbit_tty_install_sigwinch_handler(int32_t fd) {
  if (fd < 0) {
    errno = EINVAL;
    return -1;
  }
  if (moonbit_tty_sigwinch_fd >= 0) {
    moonbit_tty_sigwinch_fd = fd;
    return 0;
  }

  struct sigaction action;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART | SA_SIGINFO;
  action.sa_sigaction = moonbit_tty_sigwinch_handler;

  moonbit_tty_sigwinch_fd = fd;
  if (sigaction(SIGWINCH, &action, &moonbit_tty_previous_sigwinch_action) < 0) {
    moonbit_tty_sigwinch_fd = -1;
    return -1;
  }
  moonbit_tty_has_previous_sigwinch_action = 1;
  return 0;
}

MOONBIT_FFI_EXPORT
void
moonbit_tty_drain_sigwinch_pipe(int32_t fd) {
  unsigned char buffer[256];
  for (;;) {
    ssize_t n = read(fd, buffer, sizeof(buffer));
    if (n > 0) {
      continue;
    }
    if (n == 0) {
      return;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return;
    }
    return;
  }
}

#endif
