///|
/// Terminal input handle.
///
/// A `Reader` is an async byte reader that also exposes the terminal file
/// descriptor used by stateful terminal operations.
pub(open) trait Reader: @async/io.Reader {
  fn fd(Self) -> @async/types.Fd
  fn close(Self) -> Unit
}

///|
/// Terminal output handle.
///
/// A `Writer` is an async byte writer that also exposes the terminal file
/// descriptor used by output-side terminal queries.
pub(open) trait Writer: @async/io.Writer {
  fn fd(Self) -> @async/types.Fd
  fn close(Self) -> Unit
}

///|
pub impl Reader for @async/fs.File with fd(self) {
  @async/fs.File::fd(self)
}

///|
pub impl Reader for @async/fs.File with close(self) {
  @async/fs.File::close(self)
}

///|
pub impl Writer for @async/fs.File with fd(self) {
  @async/fs.File::fd(self)
}

///|
pub impl Writer for @async/fs.File with close(self) {
  @async/fs.File::close(self)
}

///|
pub impl Reader for @async/stdio.Input with fd(self) {
  @async/stdio.Input::fd(self)
}

///|
pub impl Reader for @async/stdio.Input with close(_) {
  ()
}

///|
pub impl Writer for @async/stdio.Output with fd(self) {
  @async/stdio.Output::fd(self)
}

///|
pub impl Writer for @async/stdio.Output with close(_) {
  ()
}
