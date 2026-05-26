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
/// Enable bracketed paste mode.
pub async fn Tty::enable_bracketed_paste(self : Self) -> Unit {
  self.write(@vt.enable_bracketed_paste)
}

///|
/// Disable bracketed paste mode.
pub async fn Tty::disable_bracketed_paste(self : Self) -> Unit {
  self.write(@vt.disable_bracketed_paste)
}

///|
/// Run `f` with bracketed paste mode enabled.
pub async fn[T] Tty::with_bracketed_paste(self : Self, f : async () -> T) -> T {
  self.enable_bracketed_paste()
  try f() catch {
    error => {
      self.disable_bracketed_paste()
      raise error
    }
  } noraise {
    value => {
      self.disable_bracketed_paste()
      value
    }
  }
}

///|
/// Mouse tracking scope for SGR mouse reports.
pub(all) enum MouseTrackingMode {
  Click
  Drag
  Motion
} derive(Eq)

///|
/// Enable SGR mouse tracking.
pub async fn Tty::enable_mouse(self : Self, mode : MouseTrackingMode) -> Unit {
  self.write(@vt.disable_mouse_motion)
  self.write(@vt.disable_mouse_drag)
  self.write(@vt.disable_mouse_click)
  self.write(@vt.enable_sgr_mouse)
  match mode {
    Click => self.write(@vt.enable_mouse_click)
    Drag => self.write(@vt.enable_mouse_drag)
    Motion => self.write(@vt.enable_mouse_motion)
  }
}

///|
/// Disable SGR mouse tracking.
pub async fn Tty::disable_mouse(self : Self) -> Unit {
  self.write(@vt.disable_mouse_motion)
  self.write(@vt.disable_mouse_drag)
  self.write(@vt.disable_mouse_click)
  self.write(@vt.disable_sgr_mouse)
}

///|
/// Run `f` with SGR mouse tracking enabled.
pub async fn[T] Tty::with_mouse(
  self : Self,
  mode : MouseTrackingMode,
  f : async () -> T,
) -> T {
  self.enable_mouse(mode)
  try f() catch {
    error => {
      self.disable_mouse()
      raise error
    }
  } noraise {
    value => {
      self.disable_mouse()
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
/// Move the terminal cursor to a 1-based row and column.
pub async fn Tty::set_cursor_position(
  self : Self,
  row : Int,
  col : Int,
) -> Unit {
  self.write(@vt.cursor_position(row, col))
}

///|
/// Cursor Up (CUU), ECMA-48.
pub async fn Tty::cursor_up(self : Self, n : Int) -> Unit {
  self.write(@vt.cursor_up(n))
}

///|
/// Cursor Forward (CUF), ECMA-48.
pub async fn Tty::cursor_forward(self : Self, n : Int) -> Unit {
  self.write(@vt.cursor_forward(n))
}

///|
/// Cursor Back (CUB), ECMA-48.
pub async fn Tty::cursor_back(self : Self, n : Int) -> Unit {
  self.write(@vt.cursor_back(n))
}

///|
/// Erase the entire current line (EL 2), ECMA-48.
pub async fn Tty::erase_line_all(self : Self) -> Unit {
  self.write(@vt.erase_line_all)
}

///|
/// Set Top and Bottom Margins (DECSTBM).
pub async fn Tty::set_top_bottom_margins(
  self : Self,
  top : Int,
  bottom : Int,
) -> Unit {
  self.write(@vt.set_top_bottom_margins(top, bottom))
}

///|
/// Reset Top and Bottom Margins (DECSTBM).
pub async fn Tty::reset_top_bottom_margins(self : Self) -> Unit {
  self.write(@vt.reset_top_bottom_margins)
}

///|
/// Reverse Index (RI), ECMA-48.
pub async fn Tty::reverse_index(self : Self) -> Unit {
  self.write(@vt.reverse_index)
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
/// Set bold or increased intensity.
pub async fn Tty::bold(self : Self) -> Unit {
  self.write(@vt.bold)
}

///|
/// Reset bold by restoring normal intensity.
pub async fn Tty::reset_bold(self : Self) -> Unit {
  self.write(@vt.reset_bold)
}

///|
/// Set italic text.
pub async fn Tty::italic(self : Self) -> Unit {
  self.write(@vt.italic)
}

///|
/// Reset italic text.
pub async fn Tty::reset_italic(self : Self) -> Unit {
  self.write(@vt.reset_italic)
}

///|
/// Set underlined text.
pub async fn Tty::underline(self : Self) -> Unit {
  self.write(@vt.underline)
}

///|
/// Reset underlined text.
pub async fn Tty::reset_underline(self : Self) -> Unit {
  self.write(@vt.reset_underline)
}

///|
/// Set reverse video.
pub async fn Tty::reverse(self : Self) -> Unit {
  self.write(@vt.reverse)
}

///|
/// Reset reverse video.
pub async fn Tty::reset_reverse(self : Self) -> Unit {
  self.write(@vt.reset_reverse)
}

///|
/// Reset all SGR style attributes.
pub async fn Tty::reset_style(self : Self) -> Unit {
  self.write(reset_style_sequence)
}
