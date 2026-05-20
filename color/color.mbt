///|
/// ANSI basic and bright colors.
pub(all) enum BasicColor {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  BrightBlack
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
} derive(Eq, Debug)

///|
/// Terminal color value for foreground and background style sequences.
///
/// `Indexed` and `Rgb` numeric values are clamped to `0..255` when a sequence
/// is constructed.
pub(all) enum Color {
  Default
  Basic(BasicColor)
  Indexed(Int)
  Rgb(Int, Int, Int)
} derive(Eq, Debug)

///|
/// Reset all SGR style attributes, ECMA-48 SGR 0.
pub let reset_style : Bytes = @vt.sgr1(0)

///|
/// Reset foreground color, ECMA-48 SGR 39.
pub let reset_foreground : Bytes = @vt.sgr1(39)

///|
/// Reset background color, ECMA-48 SGR 49.
pub let reset_background : Bytes = @vt.sgr1(49)

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
fn basic_foreground_code(color : BasicColor) -> Int {
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
fn basic_background_code(color : BasicColor) -> Int {
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
/// Construct a foreground color SGR sequence.
pub fn foreground(color : Color) -> Bytes {
  match color {
    Default => reset_foreground
    Basic(color) => @vt.sgr1(basic_foreground_code(color))
    Indexed(index) => @vt.sgr3(38, 5, clamp_byte_value(index))
    Rgb(r, g, b) =>
      @vt.sgr5(
        38,
        2,
        clamp_byte_value(r),
        clamp_byte_value(g),
        clamp_byte_value(b),
      )
  }
}

///|
/// Construct a background color SGR sequence.
pub fn background(color : Color) -> Bytes {
  match color {
    Default => reset_background
    Basic(color) => @vt.sgr1(basic_background_code(color))
    Indexed(index) => @vt.sgr3(48, 5, clamp_byte_value(index))
    Rgb(r, g, b) =>
      @vt.sgr5(
        48,
        2,
        clamp_byte_value(r),
        clamp_byte_value(g),
        clamp_byte_value(b),
      )
  }
}
