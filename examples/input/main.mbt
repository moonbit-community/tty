///|
let esc_timeout_ms : Int = 50

///|
async fn writeln(tty : @tty.Tty, line : String) -> Unit {
  tty.write(line)
  tty.write("\r\n")
}

///|
fn byte_to_hex(byte : Byte) -> String {
  let digits : ReadOnlyArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  ['0', 'x', digits[byte.to_int() / 16], digits[byte.to_int() % 16]]
}

///|
fn describe_bytes(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for i in 0..<bytes.length() {
    if i > 0 {
      builder.write_string(" ")
    }
    builder.write_string(byte_to_hex(bytes[i]))
  }
  builder.to_string()
}

///|
fn describe_modifiers(modifiers : @tty/input.KeyModifiers) -> String {
  let builder = StringBuilder()
  if modifiers.ctrl() {
    builder.write_string("Ctrl+")
  }
  if modifiers.alt() {
    builder.write_string("Alt+")
  }
  if modifiers.shift() {
    builder.write_string("Shift+")
  }
  if modifiers.meta() {
    builder.write_string("Meta+")
  }
  if modifiers.super_() {
    builder.write_string("Super+")
  }
  if modifiers.hyper() {
    builder.write_string("Hyper+")
  }
  builder.to_string()
}

///|
fn describe_media_key(code : @tty/input.MediaKeyCode) -> String {
  match code {
    Play => "MediaPlay"
    Pause => "MediaPause"
    PlayPause => "MediaPlayPause"
    Reverse => "MediaReverse"
    Stop => "MediaStop"
    FastForward => "MediaFastForward"
    Rewind => "MediaRewind"
    TrackNext => "MediaTrackNext"
    TrackPrevious => "MediaTrackPrevious"
    Record => "MediaRecord"
    LowerVolume => "MediaLowerVolume"
    RaiseVolume => "MediaRaiseVolume"
    MuteVolume => "MediaMuteVolume"
  }
}

///|
fn describe_modifier_key(code : @tty/input.ModifierKeyCode) -> String {
  match code {
    LeftShift => "LeftShift"
    LeftControl => "LeftControl"
    LeftAlt => "LeftAlt"
    LeftSuper => "LeftSuper"
    LeftHyper => "LeftHyper"
    LeftMeta => "LeftMeta"
    RightShift => "RightShift"
    RightControl => "RightControl"
    RightAlt => "RightAlt"
    RightSuper => "RightSuper"
    RightHyper => "RightHyper"
    RightMeta => "RightMeta"
    IsoLevel3Shift => "IsoLevel3Shift"
    IsoLevel5Shift => "IsoLevel5Shift"
  }
}

///|
fn describe_key(key : @tty/input.KeyEvent) -> String {
  let modifier = describe_modifiers(key.modifiers)
  let name = match key.code {
    Char(ch) => "\{ch}"
    Text => "Text"
    Enter => "Enter"
    Tab => "Tab"
    Backspace => "Backspace"
    Delete => "Delete"
    Escape => "Escape"
    Up => "Up"
    Down => "Down"
    Left => "Left"
    Right => "Right"
    Home => "Home"
    End => "End"
    PageUp => "PageUp"
    PageDown => "PageDown"
    Insert => "Insert"
    F1 => "F1"
    F2 => "F2"
    F3 => "F3"
    F4 => "F4"
    F5 => "F5"
    F6 => "F6"
    F7 => "F7"
    F8 => "F8"
    F9 => "F9"
    F10 => "F10"
    F11 => "F11"
    F12 => "F12"
    F13 => "F13"
    F14 => "F14"
    F15 => "F15"
    F16 => "F16"
    F17 => "F17"
    F18 => "F18"
    F19 => "F19"
    F20 => "F20"
    F21 => "F21"
    F22 => "F22"
    F23 => "F23"
    F24 => "F24"
    F25 => "F25"
    F26 => "F26"
    F27 => "F27"
    F28 => "F28"
    F29 => "F29"
    F30 => "F30"
    F31 => "F31"
    F32 => "F32"
    F33 => "F33"
    F34 => "F34"
    F35 => "F35"
    CapsLock => "CapsLock"
    ScrollLock => "ScrollLock"
    NumLock => "NumLock"
    PrintScreen => "PrintScreen"
    Pause => "Pause"
    Menu => "Menu"
    KeypadBegin => "KeypadBegin"
    Keypad0 => "Keypad0"
    Keypad1 => "Keypad1"
    Keypad2 => "Keypad2"
    Keypad3 => "Keypad3"
    Keypad4 => "Keypad4"
    Keypad5 => "Keypad5"
    Keypad6 => "Keypad6"
    Keypad7 => "Keypad7"
    Keypad8 => "Keypad8"
    Keypad9 => "Keypad9"
    KeypadDecimal => "KeypadDecimal"
    KeypadDivide => "KeypadDivide"
    KeypadMultiply => "KeypadMultiply"
    KeypadMinus => "KeypadMinus"
    KeypadPlus => "KeypadPlus"
    KeypadEnter => "KeypadEnter"
    KeypadEqual => "KeypadEqual"
    KeypadSeparator => "KeypadSeparator"
    Media(code) => describe_media_key(code)
    Modifier(code) => describe_modifier_key(code)
  }
  let kind = match key.kind {
    Press => ""
    Repeat => " repeat"
    Release => " release"
  }
  "event: Key\{kind} \{modifier}\{name}"
}

///|
fn describe_mouse_button(button : @tty/input.MouseButton) -> String {
  match button {
    Left => "Left"
    Middle => "Middle"
    Right => "Right"
  }
}

///|
fn describe_mouse_scroll(scroll : @tty/input.MouseScroll) -> String {
  match scroll {
    Up => "Up"
    Down => "Down"
    Left => "Left"
    Right => "Right"
  }
}

///|
fn describe_mouse_kind(kind : @tty/input.MouseEventKind) -> String {
  match kind {
    Press(button) => "Press \{describe_mouse_button(button)}"
    Release(button) => "Release \{describe_mouse_button(button)}"
    Drag(button) => "Drag \{describe_mouse_button(button)}"
    Move => "Move"
    Scroll(scroll) => "Scroll \{describe_mouse_scroll(scroll)}"
  }
}

///|
fn describe_mouse(mouse : @tty/input.MouseEvent) -> String {
  let modifier = describe_modifiers(mouse.modifiers)
  "event: Mouse \{modifier}\{describe_mouse_kind(mouse.kind)} row=\{mouse.row} col=\{mouse.col}"
}

///|
fn string_char_count(text : String) -> Int {
  let mut count = 0
  for _ in text {
    count += 1
  }
  count
}

///|
fn describe_input(input : @tty/input.InputEvent) -> String {
  match input {
    Key(key) => describe_key(key)
    Unknown(bytes) =>
      "event: Unknown \{bytes.length()} bytes [\{describe_bytes(bytes)}]"
    Paste(text) => "event: Paste \{string_char_count(text)} chars"
    FocusIn => "event: FocusIn"
    FocusOut => "event: FocusOut"
    Mouse(mouse) => describe_mouse(mouse)
  }
}

///|
fn describe_event(event : @tty.Event) -> String {
  match event {
    Input(input) => describe_input(input)
    Resize(size) => "event: Resize rows=\{size.rows} cols=\{size.cols}"
  }
}

///|
fn is_exit_input(input : @tty/input.InputEvent) -> Bool {
  match input {
    Key(key) =>
      match key.code {
        Char('c') if key.modifiers.ctrl() => true
        _ => false
      }
    _ => false
  }
}

///|
async fn run_input_events(tty : @tty.Tty) -> Unit {
  writeln(tty, "input event demo")
  writeln(tty, "Events print as they arrive. Ctrl-C exits.")
  while true {
    let event = tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    match event {
      Input(input) => {
        writeln(tty, describe_input(input))
        if is_exit_input(input) {
          writeln(tty, "exiting")
          break
        }
      }
      Resize(_) => writeln(tty, describe_event(event))
    }
  }
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  tty.with_raw_mode(() => {
    if tty.query_kitty_keyboard_support(timeout_ms=100) {
      tty.with_kitty_keyboard(() => {
        tty.with_bracketed_paste(() => {
          tty.with_focus_tracking(() => {
            tty.with_mouse(Motion, () => run_input_events(tty))
          })
        })
      })
    } else {
      tty.with_bracketed_paste(() => {
        tty.with_focus_tracking(() => {
          tty.with_mouse(Motion, () => run_input_events(tty))
        })
      })
    }
  })
}
