///|
extern "c" fn tty_isatty(fd : @async/types.Fd) -> Int = "moonbit_tty_isatty"

///|
/// Return whether a handle refers to a terminal.
///
/// Valid non-terminal handles return `false`; OS-level failures raise
/// `OSError`.
pub fn[T : Fd] isatty(fd : T) -> Bool raise {
  let fd = fd.fd()
  let rc = tty_isatty(fd)
  if rc < 0 {
    @os_error.check_errno("isatty")
    false
  } else if rc == 0 {
    false
  } else {
    true
  }
}
