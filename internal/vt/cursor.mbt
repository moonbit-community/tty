///|
/// Cursor Up (CUU), ECMA-48.
pub fn write_cursor_up(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[A")
  } else {
    write_csi1(buf, n, b'A')
  }
}

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
pub fn write_cursor_down(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[B")
  } else {
    write_csi1(buf, n, b'B')
  }
}

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
pub fn write_cursor_forward(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[C")
  } else {
    write_csi1(buf, n, b'C')
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
pub fn write_cursor_back(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[D")
  } else {
    write_csi1(buf, n, b'D')
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
pub fn write_cursor_next_line(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[E")
  } else {
    write_csi1(buf, n, b'E')
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
pub fn write_cursor_prev_line(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[F")
  } else {
    write_csi1(buf, n, b'F')
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
pub fn write_cursor_horizontal_absolute(buf : @buffer.Buffer, n : Int) -> Unit {
  if n <= 1 {
    buf.write_bytes(b"\x1b[G")
  } else {
    write_csi1(buf, n, b'G')
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
pub fn write_cursor_position(
  buf : @buffer.Buffer,
  row : Int,
  col : Int,
) -> Unit {
  let row = if row <= 1 { 1 } else { row }
  let col = if col <= 1 { 1 } else { col }
  if row == 1 && col == 1 {
    buf.write_bytes(b"\x1b[H")
  } else {
    write_csi2(buf, row, col, b'H')
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

///|
/// Device Status Report (DSR) request for cursor position, ECMA-48.
///
/// Terminals that support this request respond with a Cursor Position Report
/// (CPR): `CSI row ; col R`.
pub let request_cursor_position : Bytes = b"\x1b[6n"
