///|
pub(all) enum Event {
  Key(KeyEvent)
  Unknown(Bytes)
} derive(Eq, Debug)

///|
pub struct KeyEvent {
  code : KeyCode
  modifiers : KeyModifiers
  text : String
} derive(Eq, Debug)

///|
pub fn KeyEvent::new(
  code : KeyCode,
  modifiers? : KeyModifiers = no_modifiers,
  text? : String = "",
) -> KeyEvent {
  { code, modifiers, text }
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
  F(Int)
} derive(Eq, Debug)

///|
struct KeyModifiers(Int) derive(Eq, Debug)

///|
pub let no_modifiers : KeyModifiers = KeyModifiers(0)

///|
pub let mod_shift : KeyModifiers = KeyModifiers(1)

///|
pub let mod_alt : KeyModifiers = KeyModifiers(2)

///|
pub let mod_ctrl : KeyModifiers = KeyModifiers(4)

///|
pub let mod_meta : KeyModifiers = KeyModifiers(8)

///|
pub fn KeyModifiers::is_empty(self : Self) -> Bool {
  self.0 == 0
}

///|
pub fn KeyModifiers::contains(self : Self, modifiers : Self) -> Bool {
  (self.0 & modifiers.0) == modifiers.0
}

///|
pub fn KeyModifiers::union(self : Self, other : Self) -> Self {
  KeyModifiers(self.0 | other.0)
}

///|
pub fn KeyModifiers::has_shift(self : Self) -> Bool {
  self.contains(mod_shift)
}

///|
pub fn KeyModifiers::has_alt(self : Self) -> Bool {
  self.contains(mod_alt)
}

///|
pub fn KeyModifiers::has_ctrl(self : Self) -> Bool {
  self.contains(mod_ctrl)
}

///|
pub fn KeyModifiers::has_meta(self : Self) -> Bool {
  self.contains(mod_meta)
}

///|
pub(all) enum DecodeResult {
  Decoded(Int, Event)
  NeedMore
} derive(Eq, Debug)
