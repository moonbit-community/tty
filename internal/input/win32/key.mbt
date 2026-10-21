///|
/// `dwControlKeyState` flags from the Win32 `KEY_EVENT_RECORD`.
const RightAltPressed : Int32 = 0x0001

///|
const LeftAltPressed : Int32 = 0x0002

///|
const RightCtrlPressed : Int32 = 0x0004

///|
const LeftCtrlPressed : Int32 = 0x0008

///|
const ShiftPressed : Int32 = 0x0010

///|
const NumLockOn : Int32 = 0x0020

///|
const CapsLockOn : Int32 = 0x0080

///|
const EnhancedKey : Int32 = 0x0100

///|
/// One win32-input-mode key report, `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _`.
///
/// The fields carry the Win32 `KEY_EVENT_RECORD` values. The scan code is not
/// needed to pick a key and is not kept.
priv struct KeyReport {
  virtual_key_code : Int32
  unicode_char : Int32
  key_down : Bool
  control_key_state : Int32
  repeat_count : Int32
}

///|
/// Parse the parameters of a win32-input-mode key report into a key event.
///
/// The report shape is `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _`, as defined by the
/// Windows Terminal win32-input-mode specification. Empty parameters take the
/// specification defaults (`0`, and `1` for the repeat count). Reports that do
/// not describe a key with a terminal meaning, such as a lone modifier key,
/// return `None`.
pub fn parse_key(params : Array[Int32?]) -> @public_input.KeyEvent? {
  guard params is [vk, _, uc, kd, cs, rc] else { return None }
  let report = {
    virtual_key_code: vk.unwrap_or(0),
    unicode_char: uc.unwrap_or(0),
    key_down: kd.unwrap_or(0) == 1,
    control_key_state: cs.unwrap_or(0),
    repeat_count: rc.unwrap_or(1),
  }
  report.key_event()
}

///|
fn KeyReport::has_state(self : KeyReport, mask : Int32) -> Bool {
  (self.control_key_state & mask) != 0
}

///|
fn KeyReport::key_event(self : KeyReport) -> @public_input.KeyEvent? {
  let kind = self.kind()
  let modifiers = self.modifiers()
  let state = self.state()
  if self.named_key_code() is Some(code) {
    return Some(@public_input.KeyEvent::new(code, modifiers~, kind~, state~))
  }
  let key = code => @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
  match self.unicode_char {
    0 => control_code_from_virtual_key(self.virtual_key_code).map(key)
    0x01..<=0x1f => control_code_from_char(self.unicode_char).map(key)
    charcode =>
      charcode
      .to_char()
      .map(char => {
        if self.key_down {
          @public_input.KeyEvent::new(Char(char), modifiers~, kind~, state~, text=[
            char,
          ])
        } else {
          key(Char(char))
        }
      })
  }
}

///|
fn KeyReport::kind(self : KeyReport) -> @public_input.KeyEventKind {
  if !self.key_down {
    Release
  } else if self.repeat_count > 1 {
    Repeat
  } else {
    Press
  }
}

///|
/// AltGr is reported by Windows as Right Alt plus Left Ctrl. When it produced
/// text, the Ctrl and Alt bits describe the keyboard layout, not modifiers the
/// user pressed, so the text is reported without modifiers.
fn KeyReport::modifiers(self : KeyReport) -> @public_input.KeyModifiers {
  if self.is_alt_gr_text() {
    return @public_input.KeyModifiers::new()
  }
  @public_input.KeyModifiers::new(
    shift=self.has_state(ShiftPressed),
    alt=self.has_state(LeftAltPressed | RightAltPressed),
    ctrl=self.has_state(LeftCtrlPressed | RightCtrlPressed),
  )
}

///|
fn KeyReport::is_alt_gr_text(self : KeyReport) -> Bool {
  self.unicode_char > 0x1f &&
  self.has_state(RightAltPressed) &&
  self.has_state(LeftCtrlPressed) &&
  !self.has_state(LeftAltPressed | RightCtrlPressed)
}

///|
fn KeyReport::state(self : KeyReport) -> @public_input.KeyEventState {
  @public_input.KeyEventState::new(
    keypad=self.is_keypad(),
    caps_lock=self.has_state(CapsLockOn),
    num_lock=self.has_state(NumLockOn),
  )
}

///|
fn KeyReport::named_key_code(self : KeyReport) -> @public_input.KeyCode? {
  if self.is_keypad_enter() {
    Some(KeypadEnter)
  } else {
    key_code_from_virtual_key(self.virtual_key_code)
  }
}

///|
fn KeyReport::is_keypad(self : KeyReport) -> Bool {
  virtual_key_is_keypad(self.virtual_key_code) ||
  self.is_keypad_enter() ||
  self.is_keypad_navigation()
}

///|
/// The keypad Enter key shares `VK_RETURN` with the main Enter key and is
/// told apart by the enhanced-key flag.
fn KeyReport::is_keypad_enter(self : KeyReport) -> Bool {
  self.virtual_key_code == 0x0d && self.has_state(EnhancedKey)
}

///|
/// Navigation keys without the enhanced-key flag come from the keypad with
/// NumLock off; the dedicated navigation cluster sets the flag.
fn KeyReport::is_keypad_navigation(self : KeyReport) -> Bool {
  virtual_key_is_navigation(self.virtual_key_code) &&
  !self.has_state(EnhancedKey)
}

///|
fn key_code_from_virtual_key(vk : Int32) -> @public_input.KeyCode? {
  if vk >= 0x70 && vk <= 0x87 {
    return function_key(vk - 0x6f)
  }
  match vk {
    0x08 => Some(Backspace)
    0x09 => Some(Tab)
    0x0d => Some(Enter)
    0x13 => Some(Pause)
    0x1b => Some(Escape)
    0x21 => Some(PageUp)
    0x22 => Some(PageDown)
    0x23 => Some(End)
    0x24 => Some(Home)
    0x25 => Some(Left)
    0x26 => Some(Up)
    0x27 => Some(Right)
    0x28 => Some(Down)
    0x2c => Some(PrintScreen)
    0x2d => Some(Insert)
    0x2e => Some(Delete)
    0x5d => Some(Menu)
    0x60..<=0x69 => keypad_digit(vk - 0x60)
    0x6a => Some(KeypadMultiply)
    0x6b => Some(KeypadPlus)
    0x6c => Some(KeypadSeparator)
    0x6d => Some(KeypadMinus)
    0x6e => Some(KeypadDecimal)
    0x6f => Some(KeypadDivide)
    0x90 => Some(NumLock)
    0x91 => Some(ScrollLock)
    _ => None
  }
}

///|
/// Map a C0 control character to the key that produced it with Ctrl held.
fn control_code_from_char(charcode : Int32) -> @public_input.KeyCode? {
  match charcode {
    0x01..<=0x1a =>
      (charcode - 1 + 'a'.to_int()).to_char().map(char => Char(char))
    0x1b => Some(Escape)
    0x1c..<=0x1f =>
      (charcode - 0x1c + '4'.to_int()).to_char().map(char => Char(char))
    _ => None
  }
}

///|
/// Ctrl+Space and Ctrl+letter can arrive with no character at all; recover the
/// key from the virtual key code.
fn control_code_from_virtual_key(vk : Int32) -> @public_input.KeyCode? {
  match vk {
    0x20 => Some(Char(' '))
    0x41..<=0x5a => (vk - 0x41 + 'a'.to_int()).to_char().map(char => Char(char))
    _ => None
  }
}

///|
fn function_key(number : Int32) -> @public_input.KeyCode? {
  match number {
    1 => Some(F1)
    2 => Some(F2)
    3 => Some(F3)
    4 => Some(F4)
    5 => Some(F5)
    6 => Some(F6)
    7 => Some(F7)
    8 => Some(F8)
    9 => Some(F9)
    10 => Some(F10)
    11 => Some(F11)
    12 => Some(F12)
    13 => Some(F13)
    14 => Some(F14)
    15 => Some(F15)
    16 => Some(F16)
    17 => Some(F17)
    18 => Some(F18)
    19 => Some(F19)
    20 => Some(F20)
    21 => Some(F21)
    22 => Some(F22)
    23 => Some(F23)
    24 => Some(F24)
    _ => None
  }
}

///|
fn keypad_digit(number : Int32) -> @public_input.KeyCode? {
  match number {
    0 => Some(Keypad0)
    1 => Some(Keypad1)
    2 => Some(Keypad2)
    3 => Some(Keypad3)
    4 => Some(Keypad4)
    5 => Some(Keypad5)
    6 => Some(Keypad6)
    7 => Some(Keypad7)
    8 => Some(Keypad8)
    9 => Some(Keypad9)
    _ => None
  }
}

///|
fn virtual_key_is_keypad(vk : Int32) -> Bool {
  vk >= 0x60 && vk <= 0x6f
}

///|
fn virtual_key_is_navigation(vk : Int32) -> Bool {
  match vk {
    0x21 | 0x22 | 0x23 | 0x24 | 0x25 | 0x26 | 0x27 | 0x28 | 0x2d | 0x2e => true
    _ => false
  }
}
