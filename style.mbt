///|
let reset_style_sequence : Bytes = @vt.sgr1(0)

///|
let reset_foreground_sequence : Bytes = @vt.sgr1(39)

///|
let reset_background_sequence : Bytes = @vt.sgr1(49)

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
    @color.Black => 30
    @color.Red => 31
    @color.Green => 32
    @color.Yellow => 33
    @color.Blue => 34
    @color.Magenta => 35
    @color.Cyan => 36
    @color.White => 37
    @color.BrightBlack => 90
    @color.BrightRed => 91
    @color.BrightGreen => 92
    @color.BrightYellow => 93
    @color.BrightBlue => 94
    @color.BrightMagenta => 95
    @color.BrightCyan => 96
    @color.BrightWhite => 97
  }
}

///|
fn basic_background_code(color : @color.BasicColor) -> Int {
  match color {
    @color.Black => 40
    @color.Red => 41
    @color.Green => 42
    @color.Yellow => 43
    @color.Blue => 44
    @color.Magenta => 45
    @color.Cyan => 46
    @color.White => 47
    @color.BrightBlack => 100
    @color.BrightRed => 101
    @color.BrightGreen => 102
    @color.BrightYellow => 103
    @color.BrightBlue => 104
    @color.BrightMagenta => 105
    @color.BrightCyan => 106
    @color.BrightWhite => 107
  }
}

///|
fn foreground_sequence(color : @color.Color) -> Bytes {
  match color {
    @color.Default => reset_foreground_sequence
    @color.Basic(color) => @vt.sgr1(basic_foreground_code(color))
    @color.Indexed(index) => @vt.sgr3(38, 5, clamp_byte_value(index))
    @color.Rgb(r, g, b) =>
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
fn background_sequence(color : @color.Color) -> Bytes {
  match color {
    @color.Default => reset_background_sequence
    @color.Basic(color) => @vt.sgr1(basic_background_code(color))
    @color.Indexed(index) => @vt.sgr3(48, 5, clamp_byte_value(index))
    @color.Rgb(r, g, b) =>
      @vt.sgr5(
        48,
        2,
        clamp_byte_value(r),
        clamp_byte_value(g),
        clamp_byte_value(b),
      )
  }
}

///|
/// Enter the alternate screen buffer.
pub async fn Tty::enter_alt_screen(self : Self) -> Unit {
  self.write(@vt.enter_alt_screen)
}

///|
/// Leave the alternate screen buffer.
pub async fn Tty::leave_alt_screen(self : Self) -> Unit {
  self.write(@vt.leave_alt_screen)
}

///|
/// Run `f` with the output in the alternate screen buffer.
pub async fn[T] Tty::with_alt_screen(self : Self, f : async () -> T) -> T {
  self.enter_alt_screen()
  try f() catch {
    error => {
      self.leave_alt_screen()
      raise error
    }
  } noraise {
    value => {
      self.leave_alt_screen()
      value
    }
  }
}

///|
/// Hide the terminal cursor.
pub async fn Tty::hide_cursor(self : Self) -> Unit {
  self.write(@vt.hide_cursor)
}

///|
/// Show the terminal cursor.
pub async fn Tty::show_cursor(self : Self) -> Unit {
  self.write(@vt.show_cursor)
}

///|
/// Set the foreground color.
pub async fn Tty::set_foreground(self : Self, color : @color.Color) -> Unit {
  self.write(foreground_sequence(color))
}

///|
/// Set the background color.
pub async fn Tty::set_background(self : Self, color : @color.Color) -> Unit {
  self.write(background_sequence(color))
}

///|
/// Reset the foreground color to the terminal default.
pub async fn Tty::reset_foreground(self : Self) -> Unit {
  self.write(reset_foreground_sequence)
}

///|
/// Reset the background color to the terminal default.
pub async fn Tty::reset_background(self : Self) -> Unit {
  self.write(reset_background_sequence)
}

///|
/// Reset all SGR style attributes.
pub async fn Tty::reset_style(self : Self) -> Unit {
  self.write(reset_style_sequence)
}
