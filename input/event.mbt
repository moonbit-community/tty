///|
/// User input decoded from terminal bytes.
///
/// Unsupported, malformed, invalid UTF-8, or unclosed sequences are preserved
/// as `Unknown` bytes instead of becoming decoder errors.
pub(all) enum InputEvent {
  Key(KeyEvent)
  Mouse(MouseEvent)
  Paste(String)
  Unknown(Bytes)
} derive(Eq, Debug)

///|
/// Decoded key event.
///
/// `text` is decoded terminal text when present. It is not a grapheme, display
/// width, or cursor-motion contract.
///
/// `shifted_code` and `base_code` are available when kitty keyboard protocol
/// alternate key reports are enabled. `shifted_code` is the shifted key in the
/// active layout; `base_code` is the key in a standard PC-101 layout.
pub struct KeyEvent {
  code : KeyCode
  modifiers : KeyModifiers
  kind : KeyEventKind
  state : KeyEventState
  text : String?
  shifted_code : KeyCode?
  base_code : KeyCode?
} derive(Eq, Debug)

///|
/// Construct a key event.
pub fn KeyEvent::new(
  code : KeyCode,
  modifiers? : KeyModifiers = KeyModifiers::new(),
  text? : String,
  kind? : KeyEventKind = Press,
  state? : KeyEventState = KeyEventState::new(),
  shifted_code? : KeyCode,
  base_code? : KeyCode,
) -> KeyEvent {
  { code, modifiers, kind, state, text, shifted_code, base_code }
}

///|
/// Keyboard event action.
pub(all) enum KeyEventKind {
  Press
  Repeat
  Release
} derive(Eq, Debug)

///|
/// Logical key code decoded from terminal input.
pub(all) enum KeyCode {
  Char(Char)
  Text
  Enter
  Tab
  Backspace
  Delete
  Escape
  Up
  Down
  Left
  Right
  Home
  End
  PageUp
  PageDown
  Insert
  F1
  F2
  F3
  F4
  F5
  F6
  F7
  F8
  F9
  F10
  F11
  F12
  F13
  F14
  F15
  F16
  F17
  F18
  F19
  F20
  F21
  F22
  F23
  F24
  F25
  F26
  F27
  F28
  F29
  F30
  F31
  F32
  F33
  F34
  F35
  CapsLock
  ScrollLock
  NumLock
  PrintScreen
  Pause
  Menu
  KeypadBegin
  Keypad0
  Keypad1
  Keypad2
  Keypad3
  Keypad4
  Keypad5
  Keypad6
  Keypad7
  Keypad8
  Keypad9
  KeypadDecimal
  KeypadDivide
  KeypadMultiply
  KeypadMinus
  KeypadPlus
  KeypadEnter
  KeypadEqual
  KeypadSeparator
  Media(MediaKeyCode)
  Modifier(ModifierKeyCode)
} derive(Eq, Debug)

///|
/// Media key decoded from kitty keyboard functional key reports.
pub(all) enum MediaKeyCode {
  Play
  Pause
  PlayPause
  Reverse
  Stop
  FastForward
  Rewind
  TrackNext
  TrackPrevious
  Record
  LowerVolume
  RaiseVolume
  MuteVolume
} derive(Eq, Debug)

///|
/// Modifier key decoded from kitty keyboard functional key reports.
pub(all) enum ModifierKeyCode {
  LeftShift
  LeftControl
  LeftAlt
  LeftSuper
  LeftHyper
  LeftMeta
  RightShift
  RightControl
  RightAlt
  RightSuper
  RightHyper
  RightMeta
  IsoLevel3Shift
  IsoLevel5Shift
} derive(Eq, Debug)

///|
/// Opaque set of key modifiers.
struct KeyModifiers(Int) derive(Eq, Debug)

///|
/// Opaque set of keyboard event state flags.
struct KeyEventState(Int) derive(Eq, Debug)

///|
/// Construct a modifier set.
pub fn KeyModifiers::new(
  shift? : Bool = false,
  alt? : Bool = false,
  ctrl? : Bool = false,
  meta? : Bool = false,
  super_? : Bool = false,
  hyper? : Bool = false,
) -> KeyModifiers {
  let mut bits = 0
  if shift {
    bits = bits | 1
  }
  if alt {
    bits = bits | 2
  }
  if ctrl {
    bits = bits | 4
  }
  if meta {
    bits = bits | 8
  }
  if super_ {
    bits = bits | 16
  }
  if hyper {
    bits = bits | 32
  }
  KeyModifiers(bits)
}

///|
/// Return whether the Shift modifier is set.
pub fn KeyModifiers::shift(self : KeyModifiers) -> Bool {
  (self.0 & 1) != 0
}

///|
/// Return whether the Alt modifier is set.
pub fn KeyModifiers::alt(self : KeyModifiers) -> Bool {
  (self.0 & 2) != 0
}

///|
/// Return whether the Ctrl modifier is set.
pub fn KeyModifiers::ctrl(self : KeyModifiers) -> Bool {
  (self.0 & 4) != 0
}

///|
/// Return whether the Meta modifier is set.
pub fn KeyModifiers::meta(self : KeyModifiers) -> Bool {
  (self.0 & 8) != 0
}

///|
/// Return whether the Super modifier is set.
pub fn KeyModifiers::super_(self : KeyModifiers) -> Bool {
  (self.0 & 16) != 0
}

///|
/// Return whether the Hyper modifier is set.
pub fn KeyModifiers::hyper(self : KeyModifiers) -> Bool {
  (self.0 & 32) != 0
}

///|
/// Construct a keyboard event state set.
pub fn KeyEventState::new(
  keypad? : Bool = false,
  caps_lock? : Bool = false,
  num_lock? : Bool = false,
) -> KeyEventState {
  let mut bits = 0
  if keypad {
    bits = bits | 1
  }
  if caps_lock {
    bits = bits | 2
  }
  if num_lock {
    bits = bits | 4
  }
  KeyEventState(bits)
}

///|
/// Return whether the event originated from the keypad.
pub fn KeyEventState::keypad(self : KeyEventState) -> Bool {
  (self.0 & 1) != 0
}

///|
/// Return whether Caps Lock was active for the key event.
pub fn KeyEventState::caps_lock(self : KeyEventState) -> Bool {
  (self.0 & 2) != 0
}

///|
/// Return whether Num Lock was active for the key event.
pub fn KeyEventState::num_lock(self : KeyEventState) -> Bool {
  (self.0 & 4) != 0
}

///|
/// Decoded mouse event.
///
/// Rows and columns are 1-based terminal cell coordinates.
pub struct MouseEvent {
  kind : MouseEventKind
  row : Int
  col : Int
  modifiers : KeyModifiers
} derive(Eq, Debug)

///|
/// Construct a mouse event with optional key modifiers.
pub fn MouseEvent::new(
  kind : MouseEventKind,
  row : Int,
  col : Int,
  modifiers? : KeyModifiers = KeyModifiers::new(),
) -> MouseEvent {
  { kind, row, col, modifiers }
}

///|
/// Mouse input action decoded from an SGR mouse report.
pub(all) enum MouseEventKind {
  Press(MouseButton)
  Release(MouseButton)
  Drag(MouseButton)
  Move
  Scroll(MouseScroll)
} derive(Eq, Debug)

///|
/// Supported mouse buttons.
pub(all) enum MouseButton {
  Left
  Middle
  Right
} derive(Eq, Debug)

///|
/// Supported mouse scroll directions.
pub(all) enum MouseScroll {
  Up
  Down
  Left
  Right
} derive(Eq, Debug)
