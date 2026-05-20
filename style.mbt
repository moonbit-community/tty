///|
/// Enter the alternate screen buffer.
pub async fn Output::enter_alt_screen(self : Self) -> Unit {
  self.write(@vt.enter_alt_screen)
}

///|
/// Leave the alternate screen buffer.
pub async fn Output::leave_alt_screen(self : Self) -> Unit {
  self.write(@vt.leave_alt_screen)
}

///|
/// Run `f` with the output in the alternate screen buffer.
pub async fn[T] Output::with_alt_screen(self : Self, f : async () -> T) -> T {
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
pub async fn Output::hide_cursor(self : Self) -> Unit {
  self.write(@vt.hide_cursor)
}

///|
/// Show the terminal cursor.
pub async fn Output::show_cursor(self : Self) -> Unit {
  self.write(@vt.show_cursor)
}

///|
/// Set the foreground color.
pub async fn Output::set_foreground(self : Self, color : @color.Color) -> Unit {
  self.write(@color.foreground(color))
}

///|
/// Set the background color.
pub async fn Output::set_background(self : Self, color : @color.Color) -> Unit {
  self.write(@color.background(color))
}

///|
/// Reset the foreground color to the terminal default.
pub async fn Output::reset_foreground(self : Self) -> Unit {
  self.write(@color.reset_foreground)
}

///|
/// Reset the background color to the terminal default.
pub async fn Output::reset_background(self : Self) -> Unit {
  self.write(@color.reset_background)
}

///|
/// Reset all SGR style attributes.
pub async fn Output::reset_style(self : Self) -> Unit {
  self.write(@color.reset_style)
}
