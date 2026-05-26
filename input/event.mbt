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
pub struct KeyEvent {
  code : KeyCode
  modifiers : KeyModifiers
  text : String?
} derive(Eq, Debug)

///|
/// Construct a key event with optional modifiers and text.
pub fn KeyEvent::new(
  code : KeyCode,
  modifiers? : KeyModifiers = KeyModifiers::new(),
  text? : String,
) -> KeyEvent {
  KeyEvent::{ code, modifiers, text }
}

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
} derive(Eq, Debug)

///|
/// A single key modifier.
pub(all) enum KeyModifier {
  Shift
  Alt
  Ctrl
  Meta
} derive(Eq, Debug)

///|
/// Opaque set of key modifiers.
struct KeyModifiers(Int) derive(Eq, Debug)

///|
/// Construct a modifier set.
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
  MouseEvent::{ kind, row, col, modifiers }
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
