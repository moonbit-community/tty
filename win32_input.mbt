///|
#cfg(platform="windows")
priv enum WindowsInput {
  ByteStream(@input.EventReader)
  Console(@win32.EventReader)
}

///|
#cfg(platform="windows")
fn WindowsInput::new(
  input_fd : @async/types.Fd,
  fallback : &@async/io.Reader,
) -> WindowsInput {
  if tty_isatty(input_fd) > 0 {
    Console(@win32.EventReader::new(input_fd))
  } else {
    ByteStream(@input.EventReader::new(fallback))
  }
}

///|
#cfg(platform="windows")
fn WindowsInput::close(self : WindowsInput) -> Unit {
  match self {
    ByteStream(_) => ()
    Console(reader) => reader.close()
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_win32_console_event(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  match self.input_backend {
    Console(reader) => self.read_win32_event(reader, esc_timeout_ms)
    ByteStream(reader) => read_decoded_input_event(reader, esc_timeout_ms)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_win32_event(
  self : Self,
  reader : @win32.EventReader,
  esc_timeout_ms : Int,
) -> Event {
  for ;; {
    match reader.read_event(esc_timeout_ms~) {
      Some(Input(event)) => return Input(event)
      Some(Resize) =>
        try self.window_size() catch {
          _ => ()
        } noraise {
          size => return Resize(size)
        }
      None => fail("Windows console input reader closed")
    }
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  match self.input_backend {
    Console(reader) => reader.read_internal_event(esc_timeout_ms~)
    ByteStream(reader) => reader.read_event(esc_timeout_ms~)
  }
}

///|
#cfg(not(platform="windows"))
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}
