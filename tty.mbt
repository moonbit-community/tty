///|
/// Cursor position reported by the terminal.
///
/// Rows and columns are 1-based terminal coordinates.
pub struct CursorPosition {
  row : Int32
  col : Int32
} derive(Eq, Debug)

///|
/// Terminal event reported by the coordinated root `Tty` handle.
pub(all) enum Event {
  Input(@public_input.InputEvent)
  Resize(WindowSize)
} derive(Eq, Debug)

///|
/// Coordinated terminal input/output handle.
///
/// `Tty` is for terminal protocols that need to write a request and read the
/// response from the same terminal input stream. It does not model a screen.
struct Tty {
  input : &Reader
  input_fd : @async/types.Fd
  output : &Writer
  output_fd : @async/types.Fd
  reader : @input.EventReader
  // Root events read while a request/response query waited for its reply,
  // replayed by later `read_event` calls.
  pending_events : Array[Event]
  // Serializes output writes so a single `write`/`write_string` call lands on
  // the terminal atomically with respect to other concurrent writers.
  write_lock : @lock.Lock
}

///|
/// Create a coordinated terminal handle from input and output handles.
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty raise {
  let input = input as &Reader
  let input_fd = Fd::fd(input)
  let output = output as &Writer
  let output_fd = Fd::fd(output)
  {
    input,
    input_fd,
    output,
    output_fd,
    reader: @input.EventReader::new(input_byte_source(input, input_fd)),
    pending_events: [],
    write_lock: @lock.Lock::new(),
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty raise {
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
pub async fn Tty::read_event(
  self : Self,
  esc_timeout_ms~ : Int32 = 50,
) -> Event {
  if self.pending_events.length() > 0 {
    return self.pending_events.remove(0)
  }
  self.read_event_from_sources(esc_timeout_ms)
}

///|
/// Read the next root event from the decoded byte stream, skipping terminal
/// responses that only request/response queries consume.
async fn Tty::read_decoded_event(self : Self, esc_timeout_ms : Int32) -> Event {
  for ;; {
    match self.reader.read_event(esc_timeout_ms~) {
      Input(event) => return Input(event)
      TextAreaSize(..) =>
        if self.text_area_size_event() is Some(event) {
          return event
        }
      CursorPosition(..) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
async fn Tty::read_internal_event(
  self : Self,
  esc_timeout_ms~ : Int32 = 50,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}

///|
/// Keep a root event that arrived while a query waited for its reply.
fn Tty::defer_event(self : Self, event : @input.Event) -> Unit {
  match event {
    Input(input) => self.pending_events.push(Input(input))
    TextAreaSize(..) =>
      if self.text_area_size_event() is Some(event) {
        self.pending_events.push(event)
      }
    CursorPosition(..) => ()
    KeyboardEnhancementFlags(_) => ()
    PrimaryDeviceAttributes(_) => ()
    DynamicColor(..) => ()
  }
}

///|
/// Write bytes to the terminal output handle.
///
/// The write is serialized through an internal lock, so a single call lands on
/// the terminal atomically even when multiple tasks write concurrently. To make
/// a multi-call sequence atomic, assemble it into one buffer and issue a single
/// `write`.
pub async fn Tty::write(self : Self, data : &@async/io.Data) -> Unit {
  self.write_lock.with_lock(() => @async/io.Writer::write(self.output, data))
}

///|
/// Write a string to the terminal output handle.
///
/// The write is serialized through an internal lock, so a single call lands on
/// the terminal atomically even when multiple tasks write concurrently. To make
/// a multi-call sequence atomic, assemble it into one string and issue a single
/// `write_string`.
pub async fn Tty::write_string(self : Self, string : String) -> Unit {
  self.write_lock.with_lock(() => @async/io.Writer::write(self.output, string))
}

///|
/// Query the terminal cursor position.
///
/// The returned row and column are 1-based. User input received while waiting
/// for the terminal response is preserved for later `Tty::read_event` calls.
pub async fn Tty::query_cursor_position(
  self : Self,
  timeout_ms~ : Int32 = 50,
) -> CursorPosition? {
  @async.with_timeout_opt(timeout_ms, () => {
    self.write(@vt.request_cursor_position)
    for ;; {
      match self.read_internal_event() {
        CursorPosition(row~, col~) => return { row, col, }
        event => self.defer_event(event)
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
  timeout_ms~ : Int32 = 50,
) -> Bool {
  match
    @async.with_timeout_opt(timeout_ms, () => {
      self.write(@vt.query_keyboard_enhancement_flags)
      self.write(@vt.request_primary_device_attributes)
      for ;; {
        match self.read_internal_event() {
          KeyboardEnhancementFlags(_) => return true
          PrimaryDeviceAttributes(_) => return false
          event => self.defer_event(event)
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
  timeout_ms~ : Int32 = 50,
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
  timeout_ms~ : Int32 = 50,
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
  timeout_ms~ : Int32 = 50,
) -> @color.Rgb16? {
  self.query_dynamic_color(12, @vt.query_cursor_color, timeout_ms~)
}

///|
async fn Tty::query_dynamic_color(
  self : Self,
  expected_code : Int32,
  request : Bytes,
  timeout_ms~ : Int32,
) -> @color.Rgb16? {
  @async.with_timeout_opt(timeout_ms, () => {
    self.write(request)
    for ;; {
      match self.read_internal_event() {
        DynamicColor(code~, red~, green~, blue~) if code == expected_code =>
          return { red, green, blue, }
        event => self.defer_event(event)
      }
    }
  })
}

///|
pub extend CursorPosition with Eq::{equal, not_equal}

///|
pub extend CursorPosition with @debug.Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}
