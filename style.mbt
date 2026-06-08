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
fn foreground_sequence(color : @color.Color) -> Bytes {
  match color {
    Default => reset_foreground_sequence
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
fn background_sequence(color : @color.Color) -> Bytes {
  match color {
    Default => reset_background_sequence
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
/// Begin a synchronized update (DEC private mode 2026). Output written until the
/// matching `end_synchronized_update` is buffered by the terminal and presented
/// as one atomic frame, so a clear-then-repaint is never shown half-drawn.
/// Prefer `with_synchronized_update`, which always emits the matching end.
pub async fn Tty::begin_synchronized_update(self : Self) -> Unit {
  self.write(@vt.begin_synchronized_update)
}

///|
/// End a synchronized update (DEC private mode 2026): flush and atomically
/// present everything written since `begin_synchronized_update`.
pub async fn Tty::end_synchronized_update(self : Self) -> Unit {
  self.write(@vt.end_synchronized_update)
}

///|
/// Run `f` inside a synchronized update so the frame it draws is presented
/// atomically (no flicker from a visible clear-then-repaint). The end is always
/// emitted, even if `f` raises, so the terminal is never left with synchronized
/// output stuck on. Terminals without mode 2026 ignore the markers and `f` draws
/// as before.
pub async fn[T] Tty::with_synchronized_update(
  self : Self,
  f : async () -> T,
) -> T {
  self.begin_synchronized_update()
  try f() catch {
    error => {
      self.end_synchronized_update()
      raise error
    }
  } noraise {
    value => {
      self.end_synchronized_update()
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
/// Enable focus tracking.
pub async fn Tty::enable_focus_tracking(self : Self) -> Unit {
  self.write(@vt.enable_focus_tracking)
}

///|
/// Disable focus tracking.
pub async fn Tty::disable_focus_tracking(self : Self) -> Unit {
  self.write(@vt.disable_focus_tracking)
}

///|
/// Enable DEC auto wrap mode (DECAWM).
pub async fn Tty::enable_auto_wrap(self : Self) -> Unit {
  self.write(@vt.enable_auto_wrap)
}

///|
/// Disable DEC auto wrap mode (DECAWM).
pub async fn Tty::disable_auto_wrap(self : Self) -> Unit {
  self.write(@vt.disable_auto_wrap)
}

///|
/// Run `f` with focus tracking enabled.
pub async fn[T] Tty::with_focus_tracking(self : Self, f : async () -> T) -> T {
  self.enable_focus_tracking()
  try f() catch {
    error => {
      self.disable_focus_tracking()
      raise error
    }
  } noraise {
    value => {
      self.disable_focus_tracking()
      value
    }
  }
}

///|
const KeyboardDisambiguateEscapeCodes : Int = 1

///|
const KeyboardReportEventTypes : Int = 2

///|
const KeyboardReportAlternateKeys : Int = 4

///|
const KeyboardReportAllKeysAsEscapeCodes : Int = 8

///|
const KeyboardReportAssociatedText : Int = 16

///|
/// Kitty keyboard protocol progressive enhancement flags.
struct KeyboardEnhancementFlags(Int) derive(Eq)

///|
/// Construct kitty keyboard protocol progressive enhancement flags.
pub fn KeyboardEnhancementFlags::new(
  disambiguate_escape_codes? : Bool = false,
  report_event_types? : Bool = false,
  report_alternate_keys? : Bool = false,
  report_all_keys_as_escape_codes? : Bool = false,
  report_associated_text? : Bool = false,
) -> KeyboardEnhancementFlags {
  let mut bits = 0
  if disambiguate_escape_codes {
    bits = bits | KeyboardDisambiguateEscapeCodes
  }
  if report_event_types {
    bits = bits | KeyboardReportEventTypes
  }
  if report_alternate_keys {
    bits = bits | KeyboardReportAlternateKeys
  }
  if report_all_keys_as_escape_codes {
    bits = bits | KeyboardReportAllKeysAsEscapeCodes
  }
  if report_associated_text {
    bits = bits | KeyboardReportAssociatedText
  }
  KeyboardEnhancementFlags(bits)
}

///|
/// Enhancement flags for unambiguous key reports.
pub fn KeyboardEnhancementFlags::disambiguate() -> KeyboardEnhancementFlags {
  KeyboardEnhancementFlags::new(disambiguate_escape_codes=true)
}

///|
/// Enhancement flags for full kitty keyboard protocol reports.
pub fn KeyboardEnhancementFlags::full() -> KeyboardEnhancementFlags {
  KeyboardEnhancementFlags::new(
    disambiguate_escape_codes=true,
    report_event_types=true,
    report_alternate_keys=true,
    report_all_keys_as_escape_codes=true,
    report_associated_text=true,
  )
}

///|
/// Return the raw kitty protocol bitset.
pub fn KeyboardEnhancementFlags::bits(self : KeyboardEnhancementFlags) -> Int {
  self.0
}

///|
/// Return whether disambiguated escape-code reports are requested.
pub fn KeyboardEnhancementFlags::disambiguate_escape_codes(
  self : KeyboardEnhancementFlags,
) -> Bool {
  (self.0 & KeyboardDisambiguateEscapeCodes) != 0
}

///|
/// Return whether key repeat and release reports are requested.
pub fn KeyboardEnhancementFlags::report_event_types(
  self : KeyboardEnhancementFlags,
) -> Bool {
  (self.0 & KeyboardReportEventTypes) != 0
}

///|
/// Return whether alternate key-code reports are requested.
pub fn KeyboardEnhancementFlags::report_alternate_keys(
  self : KeyboardEnhancementFlags,
) -> Bool {
  (self.0 & KeyboardReportAlternateKeys) != 0
}

///|
/// Return whether all keys should be reported as escape codes.
pub fn KeyboardEnhancementFlags::report_all_keys_as_escape_codes(
  self : KeyboardEnhancementFlags,
) -> Bool {
  (self.0 & KeyboardReportAllKeysAsEscapeCodes) != 0
}

///|
/// Return whether associated text reports are requested.
pub fn KeyboardEnhancementFlags::report_associated_text(
  self : KeyboardEnhancementFlags,
) -> Bool {
  (self.0 & KeyboardReportAssociatedText) != 0
}

///|
/// Push kitty keyboard protocol progressive enhancement flags.
pub async fn Tty::push_keyboard_enhancement_flags(
  self : Self,
  flags : KeyboardEnhancementFlags,
) -> Unit {
  self.write(@vt.push_keyboard_enhancement_flags(flags.bits()))
}

///|
/// Pop one kitty keyboard protocol progressive enhancement flag stack entry.
pub async fn Tty::pop_keyboard_enhancement_flags(self : Self) -> Unit {
  self.write(@vt.pop_keyboard_enhancement_flags)
}

///|
/// Run `f` with kitty keyboard protocol enhancements enabled.
pub async fn[T] Tty::with_keyboard_enhancements(
  self : Self,
  flags : KeyboardEnhancementFlags,
  f : async () -> T,
) -> T {
  self.push_keyboard_enhancement_flags(flags)
  try f() catch {
    error => {
      self.pop_keyboard_enhancement_flags()
      raise error
    }
  } noraise {
    value => {
      self.pop_keyboard_enhancement_flags()
      value
    }
  }
}

///|
/// Run `f` with full kitty keyboard protocol reports enabled.
pub async fn[T] Tty::with_kitty_keyboard(self : Self, f : async () -> T) -> T {
  self.with_keyboard_enhancements(KeyboardEnhancementFlags::full(), f)
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
/// Erase the visible display (ED 2), ECMA-48.
pub async fn Tty::erase_display(self : Self) -> Unit {
  self.write(@vt.erase_display)
}

///|
/// Erase saved lines in the terminal scrollback (ED 3), xterm extension.
pub async fn Tty::erase_scrollback(self : Self) -> Unit {
  self.write(@vt.erase_scrollback)
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
