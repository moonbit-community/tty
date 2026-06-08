///|
/// Cursor position reported by the terminal.
///
/// Rows and columns are 1-based terminal coordinates.
pub struct CursorPosition {
  row : Int
  col : Int
} derive(Eq)

///|
/// Terminal event reported by the coordinated root `Tty` handle.
pub(all) enum Event {
  Input(@public_input.InputEvent)
  Resize(WindowSize)
} derive(Eq)

///|
/// Coordinated terminal input/output handle.
///
/// `Tty` is for terminal protocols that need to write a request and read the
/// response from the same terminal input stream. It does not model a screen.
struct Tty {
  input : &Reader
  output : &Writer
  reader : @input.EventReader
  pending_input : Array[@public_input.InputEvent]
}

///|
/// Create a coordinated terminal handle from input and output handles.
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty {
  let input = input as &Reader
  let output = output as &Writer
  {
    input,
    output,
    reader: @input.EventReader::new(input as &@async/io.Reader),
    pending_input: [],
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty {
  Tty::new(@async/stdio.stdin, @async/stdio.stdout)
}

///|
/// Close the underlying input and output handles.
///
/// Closing stdio-backed handles is a no-op.
pub fn Tty::close(self : Self) -> Unit {
  self.input.close()
  self.output.close()
}

///|
/// Read the next root terminal event.
///
/// `esc_timeout_ms` controls the short wait used to distinguish a standalone
/// Escape key from the start of a longer escape sequence.
pub async fn Tty::read_event(self : Self, esc_timeout_ms? : Int = 50) -> Event {
  if self.pending_input.length() > 0 {
    return Input(self.pending_input.remove(0))
  }
  self.read_event_from_sources(esc_timeout_ms)
}

///|
async fn Tty::read_decoded_input_event(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  for ;; {
    match self.reader.read_event(esc_timeout_ms~) {
      Input(event) => return Input(event)
      CursorPosition(..) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
/// Write bytes to the terminal output handle.
pub async fn Tty::write(self : Self, data : &@async/io.Data) -> Unit {
  self.output.write(data)
}

///|
/// Write a string to the terminal output handle.
pub async fn Tty::write_string(self : Self, string : String) -> Unit {
  self.output.write(string)
}

///|
/// Query the terminal cursor position.
///
/// The returned row and column are 1-based. User input received while waiting
/// for the terminal response is preserved for later `Tty::read_event` calls.
pub async fn Tty::query_cursor_position(
  self : Self,
  timeout_ms? : Int = 50,
) -> CursorPosition? {
  @async.with_timeout_opt(timeout_ms, () => {
    self.write(@vt.request_cursor_position)
    for ;; {
      match self.reader.read_event() {
        CursorPosition(row~, col~) => return { row, col }
        Input(event) => self.pending_input.push(event)
        KeyboardEnhancementFlags(_) => ()
        PrimaryDeviceAttributes(_) => ()
        DynamicColor(..) => ()
      }
    }
  })
}

///|
/// Query whether the terminal supports the kitty keyboard protocol.
///
/// User input received while waiting for terminal responses is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_kitty_keyboard_support(
  self : Self,
  timeout_ms? : Int = 50,
) -> Bool {
  match
    @async.with_timeout_opt(timeout_ms, () => {
      self.write(@vt.query_keyboard_enhancement_flags)
      self.write(@vt.request_primary_device_attributes)
      for ;; {
        match self.reader.read_event() {
          KeyboardEnhancementFlags(_) => return true
          PrimaryDeviceAttributes(_) => return false
          CursorPosition(..) => ()
          DynamicColor(..) => ()
          Input(event) => self.pending_input.push(event)
        }
      }
    }) {
    Some(supported) => supported
    None => false
  }
}

///|
/// Query the terminal default foreground color.
///
/// The returned RGB components are 16-bit values in the range `0..65535`.
/// User input received while waiting for the terminal response is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_default_foreground_color(
  self : Self,
  timeout_ms? : Int = 50,
) -> @color.Rgb16? {
  self.query_dynamic_color(10, @vt.query_default_foreground_color, timeout_ms~)
}

///|
/// Query the terminal default background color.
///
/// The returned RGB components are 16-bit values in the range `0..65535`.
/// User input received while waiting for the terminal response is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_default_background_color(
  self : Self,
  timeout_ms? : Int = 50,
) -> @color.Rgb16? {
  self.query_dynamic_color(11, @vt.query_default_background_color, timeout_ms~)
}

///|
/// Query the terminal text cursor color.
///
/// The returned RGB components are 16-bit values in the range `0..65535`.
/// User input received while waiting for the terminal response is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_cursor_color(
  self : Self,
  timeout_ms? : Int = 50,
) -> @color.Rgb16? {
  self.query_dynamic_color(12, @vt.query_cursor_color, timeout_ms~)
}

///|
async fn Tty::query_dynamic_color(
  self : Self,
  expected_code : Int,
  request : Bytes,
  timeout_ms~ : Int,
) -> @color.Rgb16? {
  @async.with_timeout_opt(timeout_ms, () => {
    self.write(request)
    for ;; {
      match self.reader.read_event() {
        DynamicColor(code~, red~, green~, blue~) if code == expected_code =>
          return { red, green, blue }
        DynamicColor(..) => ()
        CursorPosition(..) => ()
        KeyboardEnhancementFlags(_) => ()
        PrimaryDeviceAttributes(_) => ()
        Input(event) => self.pending_input.push(event)
      }
    }
  })
}
