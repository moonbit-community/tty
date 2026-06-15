///|
/// Reset all SGR style attributes (SGR 0), ECMA-48.
pub let reset_style : Bytes = b"\x1b[0m"

///|
/// Reset foreground color to terminal default (SGR 39), ECMA-48.
pub let reset_foreground : Bytes = b"\x1b[39m"

///|
/// Reset background color to terminal default (SGR 49), ECMA-48.
pub let reset_background : Bytes = b"\x1b[49m"

///|
/// Bold or increased intensity (SGR 1), ECMA-48.
pub let bold : Bytes = b"\x1b[1m"

///|
/// Normal intensity (SGR 22), ECMA-48.
pub let reset_bold : Bytes = b"\x1b[22m"

///|
/// Italic (SGR 3), ECMA-48.
pub let italic : Bytes = b"\x1b[3m"

///|
/// Not italic (SGR 23), ECMA-48.
pub let reset_italic : Bytes = b"\x1b[23m"

///|
/// Underline (SGR 4), ECMA-48.
pub let underline : Bytes = b"\x1b[4m"

///|
/// Not underlined (SGR 24), ECMA-48.
pub let reset_underline : Bytes = b"\x1b[24m"

///|
/// Reverse video (SGR 7), ECMA-48.
pub let reverse : Bytes = b"\x1b[7m"

///|
/// Positive image (SGR 27), ECMA-48.
pub let reset_reverse : Bytes = b"\x1b[27m"

///|
/// Construct an SGR sequence with one parameter.
pub fn sgr1(p1 : Int) -> Bytes {
  csi1(p1, b'm')
}

///|
/// Construct an SGR sequence with three parameters.
pub fn sgr3(p1 : Int, p2 : Int, p3 : Int) -> Bytes {
  let len1 = count_decimal_digits(p1)
  let len2 = count_decimal_digits(p2)
  let len3 = count_decimal_digits(p3)
  let buf : FixedArray[Byte] = FixedArray::make(5 + len1 + len2 + len3, 0)
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, p1, offset=2, length=len1)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p2, offset=offset + 1, length=len2)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p3, offset=offset + 1, length=len3)
  buf[offset] = b'm'
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Construct an SGR sequence with five parameters.
pub fn sgr5(p1 : Int, p2 : Int, p3 : Int, p4 : Int, p5 : Int) -> Bytes {
  let len1 = count_decimal_digits(p1)
  let len2 = count_decimal_digits(p2)
  let len3 = count_decimal_digits(p3)
  let len4 = count_decimal_digits(p4)
  let len5 = count_decimal_digits(p5)
  let buf : FixedArray[Byte] = FixedArray::make(
    7 + len1 + len2 + len3 + len4 + len5,
    0,
  )
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, p1, offset=2, length=len1)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p2, offset=offset + 1, length=len2)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p3, offset=offset + 1, length=len3)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p4, offset=offset + 1, length=len4)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p5, offset=offset + 1, length=len5)
  buf[offset] = b'm'
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn clamp_byte_value(value : Int) -> Int {
  if value < 0 {
    0
  } else if value > 255 {
    255
  } else {
    value
  }
}

///|
fn basic_foreground_code(color : @color.BasicColor) -> Int {
  match color {
    Black => 30
    Red => 31
    Green => 32
    Yellow => 33
    Blue => 34
    Magenta => 35
    Cyan => 36
    White => 37
    BrightBlack => 90
    BrightRed => 91
    BrightGreen => 92
    BrightYellow => 93
    BrightBlue => 94
    BrightMagenta => 95
    BrightCyan => 96
    BrightWhite => 97
  }
}

///|
fn basic_background_code(color : @color.BasicColor) -> Int {
  match color {
    Black => 40
    Red => 41
    Green => 42
    Yellow => 43
    Blue => 44
    Magenta => 45
    Cyan => 46
    White => 47
    BrightBlack => 100
    BrightRed => 101
    BrightGreen => 102
    BrightYellow => 103
    BrightBlue => 104
    BrightMagenta => 105
    BrightCyan => 106
    BrightWhite => 107
  }
}

///|
/// Construct the SGR sequence for a foreground color command.
pub fn set_foreground(color : @color.Color) -> Bytes {
  match color {
    Default => reset_foreground
    Basic(color) => sgr1(basic_foreground_code(color))
    Indexed(index) => sgr3(38, 5, clamp_byte_value(index))
    Rgb(r, g, b) =>
      sgr5(38, 2, clamp_byte_value(r), clamp_byte_value(g), clamp_byte_value(b))
  }
}

///|
/// Construct the SGR sequence for a background color command.
pub fn set_background(color : @color.Color) -> Bytes {
  match color {
    Default => reset_background
    Basic(color) => sgr1(basic_background_code(color))
    Indexed(index) => sgr3(48, 5, clamp_byte_value(index))
    Rgb(r, g, b) =>
      sgr5(48, 2, clamp_byte_value(r), clamp_byte_value(g), clamp_byte_value(b))
  }
}
