///|
/// A handle that exposes an OS file descriptor.
pub(open) trait Fd {
  fn fd(Self) -> @async/types.Fd raise
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
