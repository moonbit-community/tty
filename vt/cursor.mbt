///|
/// Cursor Up (CUU), ECMA-48.
pub fn cursor_up(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[A"
  } else {
    csi1(n, b'A')
  }
}

///|
/// Hide cursor, DEC private mode 25.
pub let hide_cursor : Bytes = b"\x1b[?25l"

///|
/// Show cursor, DEC private mode 25.
pub let show_cursor : Bytes = b"\x1b[?25h"

///|
/// Cursor Down (CUD), ECMA-48.
pub fn cursor_down(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[B"
  } else {
    csi1(n, b'B')
  }
}
