///|
// Microsoft win32-input-mode: CSI Vk;Sc;Uc;Kd;Cs;Rc _.
priv struct Win32Key {
  key_down : Int32
  repeat_count : Int32
  virtual_key_code : Int32
  virtual_scan_code : Int32
  unicode_char : Int32
  control_key_state : Int32
}

///|
fn parse_win32_key(params : BytesView) -> Win32Key? {
  // Bound each field before multiplication; do not accept wrapped integers.
  let values : Array[UInt32] = []
  let mut value : UInt32 = 0
  let mut present = false
  for byte in params {
    match byte {
      b'0'..<=b'9' => {
        guard value < 429496729 || (value == 429496729 && byte <= b'5') else {
          return None
        }
        value = value * 10 + byte.to_uint() - b'0'.to_uint()
        present = true
      }
      b';' => {
        values.push(
          if present {
            value
          } else if values.length() == 5 {
            1
          } else {
            0
          },
        )
        guard values.length() < 6 else { return None }
        value = 0
        present = false
      }
      _ => return None
    }
  }
  values.push(
    if present {
      value
    } else if values.length() == 5 {
      1
    } else {
      0
    },
  )
  while values.length() < 6 {
    values.push(if values.length() == 5 { 1 } else { 0 })
  }
  match values {
    [vk, sc, uc, kd, cs, rc] if vk <= 65535 &&
      sc <= 65535 &&
      uc <= 65535 &&
      kd <= 1 &&
      rc <= 65535 =>
      Some({
        virtual_key_code: vk.reinterpret_as_int(),
        virtual_scan_code: sc.reinterpret_as_int(),
        unicode_char: uc.reinterpret_as_int(),
        key_down: kd.reinterpret_as_int(),
        control_key_state: cs.reinterpret_as_int(),
        repeat_count: rc.reinterpret_as_int(),
      })
    _ => None
  }
}

///|
fn Win32Key::has_state(self : Win32Key, mask : Int32) -> Bool {
  (self.control_key_state & mask) != 0
}

///|
fn Win32Key::is_alt_gr_text(self : Win32Key) -> Bool {
  self.unicode_char > 0x1f &&
  self.has_state(0x01) &&
  self.has_state(0x08) &&
  !self.has_state(0x02 | 0x04)
}

///|
fn Win32Key::key_kind(self : Win32Key) -> @public_input.KeyEventKind {
  if self.key_down == 0 {
    Release
  } else if self.repeat_count > 1 {
    Repeat
  } else {
    Press
  }
}

///|
fn Win32Key::modifiers(self : Win32Key) -> @public_input.KeyModifiers {
  @public_input.KeyModifiers::new(
    shift=self.has_state(0x10),
    alt=self.has_state(0x03) && !self.is_alt_gr_text(),
    ctrl=self.has_state(0x0c) && !self.is_alt_gr_text(),
  )
}

///|
fn Win32Key::key_state(self : Win32Key) -> @public_input.KeyEventState {
  @public_input.KeyEventState::new(
    keypad=self.is_keypad(),
    caps_lock=self.has_state(0x80),
    num_lock=self.has_state(0x20),
  )
}

///|
fn Win32Key::key_event(
  self : Win32Key,
  pending_surrogate : Ref[Int32?],
) -> @public_input.KeyEvent? {
  let kind = self.key_kind()
  let modifiers = self.modifiers()
  let state = self.key_state()
  match self.key_code_from_virtual_key() {
    Some(code) => {
      pending_surrogate.val = None
      return Some(@public_input.KeyEvent::new(code, modifiers~, kind~, state~))
    }
    None => ()
  }
  let charcode = self.unicode_char
  if charcode == 0 {
    pending_surrogate.val = None
    return control_code_from_virtual_key(self.virtual_key_code).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if charcode >= 0x00 && charcode <= 0x1f {
    pending_surrogate.val = None
    return control_code_from_char(charcode).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if is_high_surrogate(charcode) {
    pending_surrogate.val = Some(charcode)
    return None
  }
  if is_low_surrogate(charcode) {
    let high = pending_surrogate.val
    pending_surrogate.val = None
    guard high is Some(high) else { return None }
    let char = decode_surrogate_pair(high, charcode)
    return Some(self.char_key_event(char, modifiers, kind, state))
  }
  pending_surrogate.val = None
  let char = codepoint_to_char(charcode)
  Some(self.char_key_event(char, modifiers, kind, state))
}

///|
fn Win32Key::key_code_from_virtual_key(
  self : Win32Key,
) -> @public_input.KeyCode? {
  if self.is_keypad_enter() {
    Some(KeypadEnter)
  } else {
    key_code_from_virtual_key(self.virtual_key_code)
  }
}

///|
fn Win32Key::is_keypad(self : Win32Key) -> Bool {
  virtual_key_is_keypad(self.virtual_key_code) ||
  self.is_keypad_enter() ||
  self.is_keypad_navigation()
}

///|
fn Win32Key::is_keypad_enter(self : Win32Key) -> Bool {
  self.virtual_key_code == 0x0d && self.has_state(0x100)
}

///|
fn Win32Key::is_keypad_navigation(self : Win32Key) -> Bool {
  virtual_key_is_navigation(self.virtual_key_code) && !self.has_state(0x100)
}

///|
fn Win32Key::char_key_event(
  self : Win32Key,
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
fn text_for_key(record : Win32Key, char : Char) -> String? {
  if record.key_down == 0 {
    None
  } else {
    Some([char])
  }
}

///|
fn key_code_from_virtual_key(vk : Int32) -> @public_input.KeyCode? {
  if vk >= 0x70 && vk <= 0x87 {
    return win32_function_key(vk - 0x6f)
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
fn control_code_from_char(charcode : Int32) -> @public_input.KeyCode? {
  match charcode {
    0x00 => Some(Char(' '))
    0x01..<=0x1a => Some(Char(codepoint_to_char(charcode - 1 + 'a'.to_int())))
    0x1b => Some(Char('['))
    0x1c..<=0x1f =>
      Some(Char(codepoint_to_char(charcode - 0x1c + '4'.to_int())))
    _ => None
  }
}

///|
fn control_code_from_virtual_key(vk : Int32) -> @public_input.KeyCode? {
  if vk == 0x20 {
    Some(Char(' '))
  } else if vk >= 0x41 && vk <= 0x5a {
    Some(Char(codepoint_to_char(vk - 0x41 + 'a'.to_int())))
  } else {
    None
  }
}

///|
fn win32_function_key(number : Int32) -> @public_input.KeyCode? {
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

///|
fn is_high_surrogate(code : Int32) -> Bool {
  code >= 0xd800 && code <= 0xdbff
}

///|
fn is_low_surrogate(code : Int32) -> Bool {
  code >= 0xdc00 && code <= 0xdfff
}

///|
fn decode_surrogate_pair(high : Int32, low : Int32) -> Char {
  let code = 0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00)
  codepoint_to_char(code)
}

///|
fn codepoint_to_char(code : Int32) -> Char {
  code.to_char().unwrap_or('\u{FFFD}')
}
