///|
/// Terminal input handle.
///
/// A `Reader` is an async byte reader that also exposes the terminal file
/// descriptor used by stateful terminal operations.
pub(open) trait Reader: @async/io.Reader + Fd {
  fn close(Self) -> Unit
}

///|
/// Terminal output handle.
///
/// A `Writer` is an async byte writer that also exposes the terminal file
/// descriptor used by output-side terminal queries.
pub(open) trait Writer: @async/io.Writer + Fd {
  fn close(Self) -> Unit
}

///|
/// Allow async files to serve as terminal input handles.
pub impl Reader for @async/fs.File with fn close(self) {
  @async/fs.File::close(self)
}

///|
/// Allow async files to serve as terminal output handles.
pub impl Writer for @async/fs.File with fn close(self) {
  @async/fs.File::close(self)
}

///|
/// Allow pipe readers to serve as terminal input handles.
pub impl Reader for @async/pipe.PipeRead with fn close(self) {
  @async/pipe.PipeRead::close(self)
}

///|
/// Allow pipe writers to serve as terminal output handles.
pub impl Writer for @async/pipe.PipeWrite with fn close(self) {
  @async/pipe.PipeWrite::close(self)
}

///|
/// Allow process stdin to serve as a terminal input handle.
pub impl Reader for @async/stdio.Input with fn close(_) {
  ()
}

///|
/// Allow process output handles to serve as terminal output handles.
pub impl Writer for @async/stdio.Output with fn close(_) {
  ()
}

///|
/// Allow raw file-descriptor streams to serve as terminal input handles.
/// Used for the controlling terminal (`/dev/tty`) and Windows console devices.
pub impl Reader for @async/raw_fd.RawFdStream with fn close(self) {
  @async/raw_fd.RawFdStream::close(self)
}

///|
/// Allow raw file-descriptor streams to serve as terminal output handles.
/// Used for the controlling terminal (`/dev/tty`) and Windows console devices.
pub impl Writer for @async/raw_fd.RawFdStream with fn close(self) {
  @async/raw_fd.RawFdStream::close(self)
}
