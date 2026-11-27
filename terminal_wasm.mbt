///|
/// Wasm controlling-terminal backend backed by `internal/sidecar`.
priv struct Terminal(@sidecar.Sidecar)

///|
async fn Terminal::open() -> Terminal {
  Terminal(@sidecar.open())
}

///|
fn Terminal::size(self : Terminal) -> (Int32, Int32) {
  self.0.size()
}

///|
fn Terminal::is_raw(self : Terminal) -> Bool {
  self.0.is_raw()
}

///|
async fn Terminal::set_raw(self : Terminal, on : Bool) -> Unit {
  self.0.set_raw(on)
}

///|
fn Terminal::close(self : Terminal) -> Unit {
  self.0.close()
}

///|
async fn Terminal::wait(self : Terminal) -> Unit nocancel {
  self.0.wait()
}

///|
impl @async/io.Reader for Terminal with fn _get_internal_buffer(self) {
  self.0._get_internal_buffer()
}

///|
impl @async/io.Reader for Terminal with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  self.0._direct_read(buf, offset~, max_len~) catch {
    @sidecar.Resized => raise Resized
    err => raise err
  }
}

///|
impl @async/io.Writer for Terminal with fn write_once(self, buf, offset~, len~) {
  self.0.write_once(buf, offset~, len~)
}
