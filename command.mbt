///|
/// Terminal output command.
///
/// A `Command` is inert data. It only writes bytes when passed to
/// `Tty::execute`.
pub(all) enum Command {
  Print(StringView)
  EnterAltScreen
  LeaveAltScreen
  BeginSynchronizedUpdate
  EndSynchronizedUpdate
  EnableBracketedPaste
  DisableBracketedPaste
  EnableFocusTracking
  DisableFocusTracking
  EnableAutoWrap
  DisableAutoWrap
  PushKeyboardEnhancementFlags(KeyboardEnhancementFlags)
  PopKeyboardEnhancementFlags
  HideCursor
  ShowCursor
  CursorUp(Int)
  CursorDown(Int)
  CursorForward(Int)
  CursorBack(Int)
  CursorNextLine(Int)
  CursorPrevLine(Int)
  CursorHorizontalAbsolute(Int)
  CursorPosition(Int, Int)
  EraseLineAll
  EraseLineLeft
  EraseLineRight
  EraseDisplay
  EraseScrollback
  SetTopBottomMargins(Int, Int)
  ResetTopBottomMargins
  ReverseIndex
  SetForeground(@color.Color)
  SetBackground(@color.Color)
  ResetForeground
  ResetBackground
  SetBold
  ResetBold
  SetItalic
  ResetItalic
  SetUnderline
  ResetUnderline
  SetReverse
  ResetReverse
  ResetStyle
  DisplayKittyPng(BytesView, KittyGraphicsOptions)
  DisplaySixel(BytesView)
}

///|
fn Command::write_to(self : Command, buf : @buffer.Buffer) -> Unit {
  match self {
    Print(text) => buf.write_string_utf8(text)
    EnterAltScreen => buf.write_bytes(@vt.enter_alt_screen)
    LeaveAltScreen => buf.write_bytes(@vt.leave_alt_screen)
    BeginSynchronizedUpdate => buf.write_bytes(@vt.begin_synchronized_update)
    EndSynchronizedUpdate => buf.write_bytes(@vt.end_synchronized_update)
    EnableBracketedPaste => buf.write_bytes(@vt.enable_bracketed_paste)
    DisableBracketedPaste => buf.write_bytes(@vt.disable_bracketed_paste)
    EnableFocusTracking => buf.write_bytes(@vt.enable_focus_tracking)
    DisableFocusTracking => buf.write_bytes(@vt.disable_focus_tracking)
    EnableAutoWrap => buf.write_bytes(@vt.enable_auto_wrap)
    DisableAutoWrap => buf.write_bytes(@vt.disable_auto_wrap)
    PushKeyboardEnhancementFlags(flags) =>
      @vt.write_push_keyboard_enhancement_flags(buf, flags.bits())
    PopKeyboardEnhancementFlags =>
      buf.write_bytes(@vt.pop_keyboard_enhancement_flags)
    HideCursor => buf.write_bytes(@vt.hide_cursor)
    ShowCursor => buf.write_bytes(@vt.show_cursor)
    CursorUp(n) => @vt.write_cursor_up(buf, n)
    CursorDown(n) => @vt.write_cursor_down(buf, n)
    CursorForward(n) => @vt.write_cursor_forward(buf, n)
    CursorBack(n) => @vt.write_cursor_back(buf, n)
    CursorNextLine(n) => @vt.write_cursor_next_line(buf, n)
    CursorPrevLine(n) => @vt.write_cursor_prev_line(buf, n)
    CursorHorizontalAbsolute(n) => @vt.write_cursor_horizontal_absolute(buf, n)
    CursorPosition(row, col) => @vt.write_cursor_position(buf, row, col)
    EraseLineAll => buf.write_bytes(@vt.erase_line_all)
    EraseLineLeft => buf.write_bytes(@vt.erase_line_left)
    EraseLineRight => buf.write_bytes(@vt.erase_line_right)
    EraseDisplay => buf.write_bytes(@vt.erase_display)
    EraseScrollback => buf.write_bytes(@vt.erase_scrollback)
    SetTopBottomMargins(top, bottom) =>
      @vt.write_set_top_bottom_margins(buf, top, bottom)
    ResetTopBottomMargins => buf.write_bytes(@vt.reset_top_bottom_margins)
    ReverseIndex => buf.write_bytes(@vt.reverse_index)
    SetForeground(color) => @vt.write_set_foreground(buf, color)
    SetBackground(color) => @vt.write_set_background(buf, color)
    ResetForeground => buf.write_bytes(@vt.reset_foreground)
    ResetBackground => buf.write_bytes(@vt.reset_background)
    SetBold => buf.write_bytes(@vt.bold)
    ResetBold => buf.write_bytes(@vt.reset_bold)
    SetItalic => buf.write_bytes(@vt.italic)
    ResetItalic => buf.write_bytes(@vt.reset_italic)
    SetUnderline => buf.write_bytes(@vt.underline)
    ResetUnderline => buf.write_bytes(@vt.reset_underline)
    SetReverse => buf.write_bytes(@vt.reverse)
    ResetReverse => buf.write_bytes(@vt.reset_reverse)
    ResetStyle => buf.write_bytes(@vt.reset_style)
    DisplayKittyPng(png, options) => {
      let image_id = options.image_id
      let columns = options.columns
      let rows = options.rows
      @vt.write_display_kitty_png(buf, png, image_id?, columns?, rows?)
    }
    DisplaySixel(sixel) => buf.write_bytes(sixel)
  }
}

///|
/// Execute terminal output commands with one serialized write.
pub async fn Tty::execute(self : Self, commands : Array[Command]) -> Unit {
  if commands.length() == 0 {
    return
  }
  let buf = @buffer.Buffer()
  for command in commands {
    command.write_to(buf)
  }
  self.write(buf.to_bytes())
}
