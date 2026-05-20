///|
/// Cursor position reported by the terminal.
///
/// Rows and columns are 1-based terminal coordinates.
pub struct CursorPosition {
  row : Int
  col : Int
} derive(Eq)

///|
/// Coordinated terminal input/output handle.
///
/// `Tty` is for terminal protocols that need to write a request and read the
/// response from the same terminal input stream. It does not model a screen.
struct Tty {
  input : Input
  output : Output
  reader : @input.EventReader
}

///|
fn Tty::new(input : Input, output : Output) -> Tty {
  Tty::{ input, output, reader: input.event_reader() }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty {
  Tty::new(stdin, stdout)
}

///|
/// Open the controlling terminal as one coordinated terminal handle.
pub async fn Tty::open() -> Tty {
  Tty::new(Input::open(), Output::open())
}

///|
pub fn Tty::close(self : Self) -> Unit {
  self.input.close()
  self.output.close()
}

///|
pub async fn Tty::read_event(
  self : Self,
  esc_timeout? : Int = 50,
) -> @input.Event {
  self.reader.read_event(esc_timeout~)
}

///|
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  self.input.with_raw_mode(f)
}

///|
pub async fn Tty::write(self : Self, data : &@async/io.Data) -> Unit {
  self.output.write(data)
}

///|
pub async fn Tty::write_string(self : Self, string : String) -> Unit {
  self.output.write_string(string)
}

///|
pub fn Tty::window_size(self : Self) -> WindowSize raise @os_error.OSError {
  self.output.window_size()
}

///|
pub async fn Tty::query_cursor_position(
  self : Self,
  timeout_ms? : Int = 50,
) -> CursorPosition? {
  self.write(@vt.request_cursor_position)
  match self.reader.read_cursor_position_response(timeout_ms~) {
    Some((row, col)) => Some(CursorPosition::{ row, col })
    None => None
  }
}

///|
pub async fn Tty::show_cursor(self : Self) -> Unit {
  self.output.show_cursor()
}

///|
pub async fn Tty::hide_cursor(self : Self) -> Unit {
  self.output.hide_cursor()
}

///|
pub async fn Tty::set_foreground(self : Self, color : @color.Color) -> Unit {
  self.output.set_foreground(color)
}

///|
pub async fn Tty::set_background(self : Self, color : @color.Color) -> Unit {
  self.output.set_background(color)
}

///|
pub async fn Tty::reset_foreground(self : Self) -> Unit {
  self.output.reset_foreground()
}

///|
pub async fn Tty::reset_background(self : Self) -> Unit {
  self.output.reset_background()
}

///|
pub async fn Tty::reset_style(self : Self) -> Unit {
  self.output.reset_style()
}
