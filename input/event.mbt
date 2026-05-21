///|
/// User input decoded from terminal bytes.
pub(all) enum InputEvent {
  Key(KeyEvent)
  Unknown(Bytes)
} derive(Eq, Debug)

///|
/// Terminal stream event decoded from the input byte stream.
pub(all) enum Event {
  Input(InputEvent)
  CursorPosition(row~ : Int, col~ : Int)
} derive(Eq, Debug)

///|
pub struct KeyEvent {
  code : KeyCode
  modifiers : KeyModifiers
  text : String?
} derive(Eq, Debug)

///|
pub fn KeyEvent::new(
  code : KeyCode,
  modifiers? : KeyModifiers = KeyModifiers::new(),
  text? : String,
) -> KeyEvent {
  KeyEvent::{ code, modifiers, text }
}

///|
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
} derive(Eq, Debug)

///|
pub(all) enum KeyModifier {
  Shift
  Alt
  Ctrl
  Meta
} derive(Eq, Debug)

///|
struct KeyModifiers(Int) derive(Eq, Debug)

///|
pub fn KeyModifiers::new(
  shift? : Bool = false,
  alt? : Bool = false,
  ctrl? : Bool = false,
  meta? : Bool = false,
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
  KeyModifiers(bits)
}

///|
pub fn KeyModifiers::shift(self : KeyModifiers) -> Bool {
  (self.0 & 1) != 0
}

///|
pub fn KeyModifiers::alt(self : KeyModifiers) -> Bool {
  (self.0 & 2) != 0
}

///|
pub fn KeyModifiers::ctrl(self : KeyModifiers) -> Bool {
  (self.0 & 4) != 0
}

///|
pub fn KeyModifiers::meta(self : KeyModifiers) -> Bool {
  (self.0 & 8) != 0
}
