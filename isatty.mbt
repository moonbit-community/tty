///|
extern "c" fn tty_isatty(fd : @async/types.Fd) -> Int = "moonbit_tty_isatty"

///|
/// Return whether a handle refers to a terminal.
///
/// Valid non-terminal handles return `false`; OS-level failures raise
/// `OSError`.
pub fn[T : Fd] isatty(fd : T) -> Bool raise @os_error.OSError {
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

///|
/// A handle that exposes an OS file descriptor.
pub(open) trait Fd {
  fn fd(Self) -> @async/types.Fd
}

///|
/// Allow async files to be used with file-descriptor based terminal APIs.
pub impl Fd for @async/fs.File with fn fd(self) {
  @async/fs.File::fd(self)
}

///|
/// Allow pipe readers to be used with file-descriptor based terminal APIs.
pub impl Fd for @async/pipe.PipeRead with fn fd(self) {
  @async/pipe.PipeRead::fd(self)
}

///|
/// Allow pipe writers to be used with file-descriptor based terminal APIs.
pub impl Fd for @async/pipe.PipeWrite with fn fd(self) {
  @async/pipe.PipeWrite::fd(self)
}

///|
/// Allow process stdin to be used with file-descriptor based terminal APIs.
pub impl Fd for @async/stdio.Input with fn fd(self) {
  @async/stdio.Input::fd(self)
}

///|
/// Allow process output handles to be used with file-descriptor based terminal APIs.
pub impl Fd for @async/stdio.Output with fn fd(self) {
  @async/stdio.Output::fd(self)
}
