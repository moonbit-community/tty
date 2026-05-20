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
  input : &Reader
  output : &Writer
  reader : @input.EventReader
}

///|
/// Create a coordinated terminal handle from input and output handles.
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty {
  let input = input as &Reader
  let output = output as &Writer
  Tty::{
    input,
    output,
    reader: @input.EventReader::new(input as &@async/io.Reader),
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty {
  Tty::new(@async/stdio.stdin, @async/stdio.stdout)
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
pub async fn Tty::write(self : Self, data : &@async/io.Data) -> Unit {
  self.output.write(data)
}

///|
pub async fn Tty::write_string(self : Self, string : String) -> Unit {
  self.output.write(string)
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
