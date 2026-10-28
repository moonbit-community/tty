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
///
/// A handle from `Tty::open` owns a sidecar process that holds the terminal
/// (see `sidecar/README.md`); handles from `Tty::new` and `Tty::stdio` are
/// plain streams and have no terminal state of their own.
struct Tty {
  input : &Reader
  output : &Writer
  // Decodes terminal input. The sidecar hands out VT bytes on every platform.
  reader : @input.EventReader
  pending_input : Array[@public_input.InputEvent]
  // Serializes output writes so a single `write`/`write_string` call lands on
  // the terminal atomically with respect to other concurrent writers.
  write_lock : @lock.Lock
  sidecar : @sidecar.Sidecar?
  // A resize noticed while a request/response query owned the reader; it is
  // reported by the next `read_event`.
  mut resize_pending : Bool
}

///|
/// Create a coordinated terminal handle from input and output handles.
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty {
  let input = input as &Reader
  {
    input,
    output: output as &Writer,
    reader: @input.EventReader::new(input as &@async/io.Reader),
    pending_input: [],
    write_lock: @lock.Lock::new(),
    sidecar: None,
    resize_pending: false,
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty {
  Tty::new(@async/stdio.stdin, @async/stdio.stdout)
}

///|
/// Open the controlling terminal as one coordinated terminal handle.
///
/// The terminal is held by a sidecar process, the executable named by
/// `TTY_SIDECAR` or the one embedded for this platform (see
/// `sidecar/README.md`). Input, resize events and output all go through it.
pub async fn Tty::open() -> Tty {
  let sidecar = @sidecar.open()
  {
    input: sidecar,
    output: sidecar,
    reader: @input.EventReader::new(sidecar as &@async/io.Reader),
    pending_input: [],
    write_lock: @lock.Lock::new(),
    sidecar: Some(sidecar),
    resize_pending: false,
  }
}

///|
/// Close the underlying input and output handles.
///
/// Closing stdio-backed handles is a no-op. For a handle from `Tty::open`
/// this ends the sidecar, which restores the terminal, and reaps it.
pub async fn Tty::close(self : Self) -> Unit {
  self.input.close()
  self.output.close()
  if self.sidecar is Some(sidecar) {
    sidecar.wait()
  }
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
  if self.pending_input.length() > 0 {
    return Input(self.pending_input.remove(0))
  }
  for ;; {
    if self.resize_pending {
      self.resize_pending = false
      return Resize(self.window_size())
    }
    try read_decoded_input_event(self.reader, esc_timeout_ms) catch {
      @sidecar.Resized => self.resize_pending = true
      error => raise error
    } noraise {
      event => return event
    }
  }
}

///|
async fn read_decoded_input_event(
  reader : @input.EventReader,
  esc_timeout_ms : Int32,
) -> Event {
  for ;; {
    match reader.read_event(esc_timeout_ms~) {
      Input(event) => return Input(event)
      CursorPosition(..) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
/// Next low-level stream event for request/response queries. A resize seen
/// meanwhile is kept for the next `read_event`.
async fn Tty::read_internal_event(
  self : Self,
  esc_timeout_ms~ : Int32 = 50,
) -> @input.Event {
  for ;; {
    try self.reader.read_event(esc_timeout_ms~) catch {
      @sidecar.Resized => self.resize_pending = true
      error => raise error
    } noraise {
      event => return event
    }
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
  timeout_ms~ : Int32 = 50,
) -> Bool {
  @async.with_timeout_opt(timeout_ms, () => {
    self.write(@vt.query_keyboard_enhancement_flags)
    self.write(@vt.request_primary_device_attributes)
    for ;; {
      match self.read_internal_event() {
        KeyboardEnhancementFlags(_) => return true
        PrimaryDeviceAttributes(_) => return false
        CursorPosition(..) => ()
        DynamicColor(..) => ()
        Input(event) => self.pending_input.push(event)
      }
    }
  }).unwrap_or(false)
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
        DynamicColor(..) => ()
        CursorPosition(..) => ()
        KeyboardEnhancementFlags(_) => ()
        PrimaryDeviceAttributes(_) => ()
        Input(event) => self.pending_input.push(event)
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
