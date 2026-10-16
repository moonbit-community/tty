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
  esc_timeout_ms : Int32,
) -> Event {
  self.ensure_win32_input_mode()
  if self.pending_input.length() > 0 {
    return Input(self.pending_input.remove(0))
  }
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
  esc_timeout_ms : Int32,
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
  esc_timeout_ms : Int32,
) -> @input.Event {
  self.ensure_win32_input_mode()
  match self.input_backend {
    Console(reader) => reader.read_internal_event(esc_timeout_ms~)
    ByteStream(reader) => reader.read_event(esc_timeout_ms~)
  }
}

///|
#cfg(platform="windows")
priv enum Win32InputMode {
  Unchecked
  Unavailable
  Enabled(previously_enabled~ : Bool)
} derive(Eq)

///|
#cfg(platform="windows")
async fn Tty::prepare_input_protocol(self : Tty) -> Unit {
  self.ensure_win32_input_mode()
}

///|
#cfg(not(platform="windows"))
fn Tty::prepare_input_protocol(_self : Tty) -> Unit {
  ()
}

///|
#cfg(platform="windows")
async fn Tty::ensure_win32_input_mode(self : Tty) -> Unit {
  guard self.win32_input_mode is Unchecked &&
    self.input_backend is Console(reader) &&
    tty_isatty(self.output_fd) > 0 &&
    console_input_is_raw(self.input_fd) else {
    return
  }
  // Read through the sole console pump, preserving user input and resize.
  // Query before changing anything, including when the terminal already has
  // this mode enabled (for example in a nested application).
  let mode = @async.with_timeout_opt(100, () => {
    self.write(@vt.query_win32_input_mode)
    for ;; {
      match reader.read_internal_event() {
        Win32InputMode(status) => return status
        Input(event) => self.pending_input.push(event)
        _ => ()
      }
    }
  })
  match mode {
    Some(1) => self.win32_input_mode = Enabled(previously_enabled=true)
    Some(2) => {
      // Record ownership before writing so cancellation/error cleanup can
      // restore the terminal even if the write completed only partially.
      self.win32_input_mode = Enabled(previously_enabled=false)
      self.write(@vt.enable_win32_input_mode)
    }
    _ => self.win32_input_mode = Unavailable
  }
}

///|
#cfg(platform="windows")
fn Tty::restore_win32_input_mode(
  self : Tty,
  target : Win32InputMode,
) -> Unit raise @os_error.OSError {
  if self.win32_input_mode != target {
    let enable = match target {
      Enabled(..) => Some(true)
      _ =>
        match self.win32_input_mode {
          Enabled(previously_enabled~) => Some(previously_enabled)
          _ => None
        }
    }
    if enable is Some(enable) {
      let sequence = if enable {
        @vt.enable_win32_input_mode
      } else {
        @vt.disable_win32_input_mode
      }
      if write_console_mode_sequence(self.output_fd, sequence) < 0 {
        @os_error.check_errno("restore win32-input-mode")
      }
    }
    self.win32_input_mode = target
  }
}

///|
#cfg(platform="windows")
extern "c" fn console_input_is_raw(fd : @async/types.Fd) -> Bool = "moonbit_tty_console_input_is_raw"

///|
#cfg(platform="windows")
#borrow(sequence)
extern "c" fn write_console_mode_sequence(
  fd : @async/types.Fd,
  sequence : Bytes,
) -> Int32 = "moonbit_tty_write_console_mode_sequence"

///|
#cfg(not(platform="windows"))
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int32,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}
