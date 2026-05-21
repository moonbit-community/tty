///|
extern "c" fn tty_isatty(fd : @async/types.Fd) -> Int = "moonbit_tty_isatty"

///|
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
pub(open) trait Fd {
  fn fd(Self) -> @async/types.Fd
}

///|
pub impl Fd for @async/types.Fd with fd(self) {
  self
}

///|
pub impl Fd for @async/fs.File with fd(self) {
  @async/fs.File::fd(self)
}

///|
pub impl Fd for @async/pipe.PipeRead with fd(self) {
  @async/pipe.PipeRead::fd(self)
}

///|
pub impl Fd for @async/pipe.PipeWrite with fd(self) {
  @async/pipe.PipeWrite::fd(self)
}

///|
pub impl Fd for @async/stdio.Input with fd(self) {
  @async/stdio.Input::fd(self)
}

///|
pub impl Fd for @async/stdio.Output with fd(self) {
  @async/stdio.Output::fd(self)
}
