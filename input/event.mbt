///|
/// User input decoded from terminal bytes.
///
/// Unsupported, malformed, invalid UTF-8, or unclosed sequences are preserved
/// as `Unknown` bytes instead of becoming decoder errors.
#derive(Eq, Debug)
pub(all) enum InputEvent {
  Key(KeyEvent)
  Mouse(MouseEvent)
  Paste(String)
  FocusIn
  FocusOut
  Unknown(Bytes)
}

///|
/// Decoded key event.
///
/// `text` is decoded terminal text when present. It is not a grapheme, display
/// width, or cursor-motion contract.
///
/// `shifted_code` and `base_code` are available when kitty keyboard protocol
/// alternate key reports are enabled. `shifted_code` is the shifted key in the
/// active layout; `base_code` is the key in a standard PC-101 layout.
#derive(Eq, Debug)
pub struct KeyEvent {
  code : KeyCode
  modifiers : KeyModifiers
  kind : KeyEventKind
  state : KeyEventState
  text : String?
  shifted_code : KeyCode?
  base_code : KeyCode?
}

///|
/// Construct a key event.
pub fn KeyEvent::new(
  code : KeyCode,
  modifiers~ : KeyModifiers = KeyModifiers::new(),
  text? : String,
  kind~ : KeyEventKind = Press,
  state~ : KeyEventState = KeyEventState::new(),
  shifted_code? : KeyCode,
  base_code? : KeyCode,
) -> KeyEvent {
  { code, modifiers, kind, state, text, shifted_code, base_code, }
}

///|
/// Keyboard event action.
#derive(Eq, Debug)
pub(all) enum KeyEventKind {
  Press
  Repeat
  Release
}

///|
/// Logical key code decoded from terminal input.
#derive(Eq, Debug)
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
}

///|
/// Media key decoded from kitty keyboard functional key reports.
#derive(Eq, Debug)
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
}

///|
/// Modifier key decoded from kitty keyboard functional key reports.
#derive(Eq, Debug)
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
}

///|
/// Opaque set of key modifiers.
#derive(Eq, Debug)
struct KeyModifiers(Int32)

///|
/// Opaque set of keyboard event state flags.
#derive(Eq, Debug)
struct KeyEventState(Int32)

///|
/// Construct a modifier set.
pub fn KeyModifiers::new(
  shift~ : Bool = false,
  alt~ : Bool = false,
  ctrl~ : Bool = false,
  meta~ : Bool = false,
  super_~ : Bool = false,
  hyper~ : Bool = false,
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
  keypad~ : Bool = false,
  caps_lock~ : Bool = false,
  num_lock~ : Bool = false,
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
#derive(Eq, Debug)
pub struct MouseEvent {
  kind : MouseEventKind
  row : Int32
  col : Int32
  modifiers : KeyModifiers
}

///|
/// Construct a mouse event with optional key modifiers.
pub fn MouseEvent::new(
  kind : MouseEventKind,
  row : Int32,
  col : Int32,
  modifiers~ : KeyModifiers = KeyModifiers::new(),
) -> MouseEvent {
  { kind, row, col, modifiers, }
}

///|
/// Mouse input action decoded from an SGR mouse report.
#derive(Eq, Debug)
pub(all) enum MouseEventKind {
  Press(MouseButton)
  Release(MouseButton)
  Drag(MouseButton)
  Move
  Scroll(MouseScroll)
}

///|
/// Supported mouse buttons.
#derive(Eq, Debug)
pub(all) enum MouseButton {
  Left
  Middle
  Right
}

///|
/// Supported mouse scroll directions.
#derive(Eq, Debug)
pub(all) enum MouseScroll {
  Up
  Down
  Left
  Right
}

///|
pub extend InputEvent with Eq::{equal, not_equal}

///|
pub extend InputEvent with @debug.Debug::{to_repr}

///|
pub extend KeyEvent with Eq::{equal, not_equal}

///|
pub extend KeyEvent with @debug.Debug::{to_repr}

///|
pub extend KeyEventKind with Eq::{equal, not_equal}

///|
pub extend KeyEventKind with @debug.Debug::{to_repr}

///|
pub extend KeyCode with Eq::{equal, not_equal}

///|
pub extend KeyCode with @debug.Debug::{to_repr}

///|
pub extend MediaKeyCode with Eq::{equal, not_equal}

///|
pub extend MediaKeyCode with @debug.Debug::{to_repr}

///|
pub extend ModifierKeyCode with Eq::{equal, not_equal}

///|
pub extend ModifierKeyCode with @debug.Debug::{to_repr}

///|
pub extend KeyModifiers with Eq::{equal, not_equal}

///|
pub extend KeyModifiers with @debug.Debug::{to_repr}

///|
pub extend KeyEventState with Eq::{equal, not_equal}

///|
pub extend KeyEventState with @debug.Debug::{to_repr}

///|
pub extend MouseEvent with Eq::{equal, not_equal}

///|
pub extend MouseEvent with @debug.Debug::{to_repr}

///|
pub extend MouseEventKind with Eq::{equal, not_equal}

///|
pub extend MouseEventKind with @debug.Debug::{to_repr}

///|
pub extend MouseButton with Eq::{equal, not_equal}

///|
pub extend MouseButton with @debug.Debug::{to_repr}

///|
pub extend MouseScroll with Eq::{equal, not_equal}

///|
pub extend MouseScroll with @debug.Debug::{to_repr}
