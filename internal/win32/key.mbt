///|
pub fn KeyRecord::is_down(self : KeyRecord) -> Bool {
  self.key_down != 0
}

///|
pub fn KeyRecord::repeat_count(self : KeyRecord) -> Int {
  if self.repeat_count > 0 {
    self.repeat_count
  } else {
    1
  }
}

///|
pub fn KeyRecord::text_uses_decoder(self : KeyRecord) -> Bool {
  self.key_down != 0 && !self.has_direct_key_metadata()
}

///|
fn KeyRecord::has_direct_key_metadata(self : KeyRecord) -> Bool {
  (self.has_keyboard_modifier() && !self.is_alt_gr_text()) || self.is_keypad()
}

///|
fn KeyRecord::has_keyboard_modifier(self : KeyRecord) -> Bool {
  has_state(
    self.control_key_state,
    ShiftPressed |
    LeftAltPressed |
    RightAltPressed |
    LeftCtrlPressed |
    RightCtrlPressed,
  )
}

///|
fn KeyRecord::is_alt_gr_text(self : KeyRecord) -> Bool {
  let alt_gr_state = RightAltPressed | LeftCtrlPressed
  self.key_down != 0 &&
  self.unicode_char > 0x1f &&
  (self.control_key_state & alt_gr_state) == alt_gr_state &&
  !has_state(self.control_key_state, LeftAltPressed | RightCtrlPressed)
}

///|
pub fn KeyRecord::text(
  self : KeyRecord,
  pending_surrogate : Ref[Int],
) -> String? {
  if self.key_down == 0 {
    return None
  }
  let charcode = self.unicode_char
  if charcode == 0 {
    pending_surrogate.val = 0
    return None
  }
  if is_high_surrogate(charcode) {
    pending_surrogate.val = charcode
    return None
  }
  if is_low_surrogate(charcode) {
    let high = pending_surrogate.val
    pending_surrogate.val = 0
    guard high != 0 else { return None }
    let char = decode_surrogate_pair(high, charcode)
    return Some([char])
  }
  pending_surrogate.val = 0
  Some([charcode.unsafe_to_char()])
}

///|
pub fn KeyRecord::input(
  self : KeyRecord,
  pending_surrogate : Ref[Int],
) -> @public_input.InputEvent? {
  guard self.key_event(pending_surrogate) is Some(event) else { return None }
  Some(Key(event))
}

///|
fn KeyRecord::key_kind(self : KeyRecord) -> @public_input.KeyEventKind {
  if self.key_down == 0 {
    Release
  } else if self.repeat_count > 1 {
    Repeat
  } else {
    Press
  }
}

///|
fn KeyRecord::modifiers(self : KeyRecord) -> @public_input.KeyModifiers {
  modifiers_from_control_key_state(self.control_key_state)
}

///|
fn KeyRecord::key_state(self : KeyRecord) -> @public_input.KeyEventState {
  @public_input.KeyEventState::new(
    keypad=self.is_keypad(),
    caps_lock=has_state(self.control_key_state, CapsLockOn),
    num_lock=has_state(self.control_key_state, NumLockOn),
  )
}

///|
fn KeyRecord::key_event(
  self : KeyRecord,
  pending_surrogate : Ref[Int],
) -> @public_input.KeyEvent? {
  let kind = self.key_kind()
  let modifiers = self.modifiers()
  let state = self.key_state()
  match self.key_code_from_virtual_key() {
    Some(code) => {
      pending_surrogate.val = 0
      return Some(@public_input.KeyEvent::new(code, modifiers~, kind~, state~))
    }
    None => ()
  }
  let charcode = self.unicode_char
  if charcode == 0 {
    pending_surrogate.val = 0
    return control_code_from_virtual_key(self.virtual_key_code).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if charcode >= 0x00 && charcode <= 0x1f {
    pending_surrogate.val = 0
    return control_code_from_char(charcode).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if is_high_surrogate(charcode) {
    pending_surrogate.val = charcode
    return None
  }
  if is_low_surrogate(charcode) {
    let high = pending_surrogate.val
    pending_surrogate.val = 0
    guard high != 0 else { return None }
    let char = decode_surrogate_pair(high, charcode)
    return Some(self.char_key_event(char, modifiers, kind, state))
  }
  pending_surrogate.val = 0
  let char = charcode.unsafe_to_char()
  Some(self.char_key_event(char, modifiers, kind, state))
}

///|
fn KeyRecord::key_code_from_virtual_key(
  self : KeyRecord,
) -> @public_input.KeyCode? {
  if self.is_keypad_enter() {
    Some(KeypadEnter)
  } else {
    key_code_from_virtual_key(self.virtual_key_code)
  }
}

///|
fn KeyRecord::is_keypad(self : KeyRecord) -> Bool {
  virtual_key_is_keypad(self.virtual_key_code) ||
  self.is_keypad_enter() ||
  self.is_keypad_navigation()
}

///|
fn KeyRecord::is_keypad_enter(self : KeyRecord) -> Bool {
  self.virtual_key_code == 0x0d &&
  has_state(self.control_key_state, EnhancedKey)
}

///|
fn KeyRecord::is_keypad_navigation(self : KeyRecord) -> Bool {
  virtual_key_is_navigation(self.virtual_key_code) &&
  !has_state(self.control_key_state, EnhancedKey)
}

///|
fn KeyRecord::char_key_event(
  self : KeyRecord,
  char : Char,
  modifiers : @public_input.KeyModifiers,
  kind : @public_input.KeyEventKind,
  state : @public_input.KeyEventState,
) -> @public_input.KeyEvent {
  match text_for_key(self, char) {
    Some(text) =>
      @public_input.KeyEvent::new(Char(char), modifiers~, kind~, state~, text~)
    None => @public_input.KeyEvent::new(Char(char), modifiers~, kind~, state~)
  }
}

///|
fn text_for_key(record : KeyRecord, char : Char) -> String? {
  if record.key_down == 0 {
    None
  } else {
    Some([char])
  }
}

///|
fn key_code_from_virtual_key(vk : Int) -> @public_input.KeyCode? {
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
    0x6a => Some(KeypadMultiply)
    0x6b => Some(KeypadPlus)
    0x6c => Some(KeypadSeparator)
    0x6d => Some(KeypadMinus)
    0x6e => Some(KeypadDecimal)
    0x6f => Some(KeypadDivide)
    0x90 => Some(NumLock)
    0x91 => Some(ScrollLock)
    _ => if vk >= 0x60 && vk <= 0x69 { keypad_digit(vk - 0x60) } else { None }
  }
}

///|
fn control_code_from_char(charcode : Int) -> @public_input.KeyCode? {
  match charcode {
    0x00 => Some(Char(' '))
    0x01..=0x1a => Some(Char((charcode - 1 + 'a'.to_int()).unsafe_to_char()))
    0x1b => Some(Escape)
    0x1c..=0x1f => Some(Char((charcode - 0x1c + '4'.to_int()).unsafe_to_char()))
    _ => None
  }
}

///|
fn control_code_from_virtual_key(vk : Int) -> @public_input.KeyCode? {
  if vk == 0x20 {
    Some(Char(' '))
  } else if vk >= 0x41 && vk <= 0x5a {
    Some(Char((vk - 0x41 + 'a'.to_int()).unsafe_to_char()))
  } else {
    None
  }
}

///|
fn function_key(number : Int) -> @public_input.KeyCode? {
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
fn keypad_digit(number : Int) -> @public_input.KeyCode? {
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
fn virtual_key_is_keypad(vk : Int) -> Bool {
  vk >= 0x60 && vk <= 0x6f
}

///|
fn virtual_key_is_navigation(vk : Int) -> Bool {
  match vk {
    0x21 | 0x22 | 0x23 | 0x24 | 0x25 | 0x26 | 0x27 | 0x28 | 0x2d | 0x2e => true
    _ => false
  }
}

///|
fn has_state(state : Int, mask : Int) -> Bool {
  (state & mask) != 0
}

///|
fn is_high_surrogate(code : Int) -> Bool {
  code >= 0xd800 && code <= 0xdbff
}

///|
fn is_low_surrogate(code : Int) -> Bool {
  code >= 0xdc00 && code <= 0xdfff
}

///|
fn decode_surrogate_pair(high : Int, low : Int) -> Char {
  let code = 0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00)
  code.unsafe_to_char()
}
