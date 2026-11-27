///|
/// Native controlling-terminal backend backed by `moonbitlang/core/async/tty`.
#warnings("-14")
priv struct Terminal {
  tty : @core_tty.Tty
  read_buf : @async/io.ReaderBuffer
  mut raw : Bool
}

///|
#warnings("-14")
async fn Terminal::open() -> Terminal {
  {
    tty: @core_tty.open(),
    read_buf: @async/io.ReaderBuffer::new(),
    raw: false,
  }
}

///|
fn Terminal::size(self : Terminal) -> (Int32, Int32) raise @os_error.OSError {
  self.tty.size() catch {
    @core_os_error.OsError(_, raw_code~, context~) =>
      raise OSError(raw_code, context~)
    err => raise OSError(@os_error.errno_ENOTSUP, context=err.to_string())
  }
}

///|
fn Terminal::is_raw(self : Terminal) -> Bool {
  self.raw
}

///|
#warnings("-unused_async")
async fn Terminal::set_raw(self : Terminal, on : Bool) -> Unit {
  if on {
    self.tty.enter_raw_mode()
  } else {
    self.tty.leave_raw_mode()
  }
  self.raw = on
}

///|
fn Terminal::close(self : Terminal) -> Unit {
  if self.raw {
    self.tty.leave_raw_mode() catch {
      _ => ()
    }
    self.raw = false
  }
}

///|
#warnings("-unused_async")
async fn Terminal::wait(self : Terminal) -> Unit nocancel {
  ignore(self)
}

///|
impl @async/io.Reader for Terminal with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
impl @async/io.Reader for Terminal with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  match self.tty.wait_resize() {
    Resize => raise Resized
    Input =>
      self.tty.read_into(buf.mut_view(start=offset, end=offset + max_len))
  }
}

///|
impl @async/io.Writer for Terminal with fn write_once(self, buf, offset~, len~) {
  self.tty.write(buf[offset:offset + len])
  len
}
