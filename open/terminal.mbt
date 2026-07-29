///|
/// A terminal stream backed by a raw OS file descriptor.
///
/// Wraps `@async/raw_fd.RawFdStream` so raw descriptors — the controlling
/// terminal, console devices, or caller-provided fds — can be used with
/// `@tty` handles such as `@tty.Tty::new` and `@tty.isatty`.
pub struct Terminal(@async/raw_fd.RawFdStream)

///|
pub impl @async/io.Reader for Terminal with fn _get_internal_buffer(self) {
  @async/io.Reader::_get_internal_buffer(self.0)
}

///|
pub impl @async/io.Reader for Terminal with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  @async/io.Reader::_direct_read(self.0, buf, offset~, max_len~)
}

///|
pub impl @async/io.Writer for Terminal with fn write_once(
  self,
  buf,
  offset~,
  len~,
) {
  @async/io.Writer::write_once(self.0, buf, offset~, len~)
}

///|
/// Expose the wrapped raw descriptor for file-descriptor based terminal APIs.
pub impl @tty.Fd for Terminal with fn fd(self) {
  self.0.fd
}

///|
/// Allow raw terminal streams to serve as terminal input handles.
pub impl @tty.Reader for Terminal with fn close(self) {
  self.0.close()
}

///|
/// Allow raw terminal streams to serve as terminal output handles.
pub impl @tty.Writer for Terminal with fn close(self) {
  self.0.close()
}
