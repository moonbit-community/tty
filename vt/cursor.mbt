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

///|
/// Cursor Forward (CUF), ECMA-48.
pub fn cursor_forward(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[C"
  } else {
    csi1(n, b'C')
  }
}

///|
/// Cursor Backward (CUB), ECMA-48.
pub fn cursor_back(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[D"
  } else {
    csi1(n, b'D')
  }
}

///|
/// Cursor Next Line (CNL), ECMA-48.
pub fn cursor_next_line(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[E"
  } else {
    csi1(n, b'E')
  }
}

///|
/// Cursor Previous Line (CPL), ECMA-48.
pub fn cursor_prev_line(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[F"
  } else {
    csi1(n, b'F')
  }
}

///|
/// Cursor Character Absolute (CHA), ECMA-48.
pub fn cursor_horizontal_absolute(n : Int) -> Bytes {
  if n <= 1 {
    b"\x1b[G"
  } else {
    csi1(n, b'G')
  }
}

///|
/// Cursor Position (CUP), ECMA-48.
///
/// `row` and `col` are 1-based. Values less than 1 are treated as 1.
pub fn cursor_position(row : Int, col : Int) -> Bytes {
  let row = if row <= 1 { 1 } else { row }
  let col = if col <= 1 { 1 } else { col }
  if row == 1 && col == 1 {
    b"\x1b[H"
  } else {
    csi2(row, col, b'H')
  }
}
