///|
const Esc : Byte = b'\x1b'

///|
fn byte_slice(bytes : Bytes, len : Int) -> Bytes {
  bytes.view(end=len).to_owned()
}

///|
fn decoded_key(
  consumed : Int,
  code : KeyCode,
  modifiers? : KeyModifiers = no_modifiers,
  text? : String = "",
) -> DecodeResult {
  Decoded(consumed, Key(KeyEvent::new(code, modifiers~, text~)))
}

///|
fn unknown(bytes : Bytes, consumed : Int) -> DecodeResult {
  Decoded(consumed, Unknown(byte_slice(bytes, consumed)))
}

///|
fn char_text(char : Char) -> String {
  String::from_array([char])
}

///|
fn is_continuation(byte : Byte) -> Bool {
  let n = byte.to_int()
  n >= 0x80 && n <= 0xBF
}

///|
fn is_digit(byte : Byte) -> Bool {
  byte >= b'0' && byte <= b'9'
}

///|
fn parse_utf8(bytes : Bytes, more : Bool) -> DecodeResult {
  let len = bytes.length()
  let b0 = bytes[0].to_int()
  let needed = match b0 {
    0xC2..=0xDF => 2
    0xE0..=0xEF => 3
    0xF0..=0xF4 => 4
    _ => return unknown(bytes, 1)
  }
  guard len >= needed else {
    if more {
      return NeedMore
    } else {
      return unknown(bytes, len)
    }
  }
  for i in 1..<needed {
    guard is_continuation(bytes[i]) else { return unknown(bytes, 1) }
  }
  let b1 = bytes[1].to_int()
  let valid = match b0 {
    0xC2..=0xDF => true
    0xE0 => b1 >= 0xA0
    0xE1..=0xEC | 0xEE..=0xEF => true
    0xED => b1 <= 0x9F
    0xF0 => b1 >= 0x90
    0xF1..=0xF3 => true
    0xF4 => b1 <= 0x8F
    _ => false
  }
  guard valid else { return unknown(bytes, 1) }
  let codepoint = match needed {
    2 => ((b0 & 0x1F) << 6) | (b1 & 0x3F)
    3 => {
      let b2 = bytes[2].to_int()
      ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
    }
    4 => {
      let b2 = bytes[2].to_int()
      let b3 = bytes[3].to_int()
      ((b0 & 0x07) << 18) |
      ((b1 & 0x3F) << 12) |
      ((b2 & 0x3F) << 6) |
      (b3 & 0x3F)
    }
    _ => abort("unreachable")
  }
  match codepoint.to_char() {
    Some(char) => decoded_key(needed, Char(char), text=char_text(char))
    None => unknown(bytes, needed)
  }
}

///|
fn control_key(bytes : Bytes, byte : Byte) -> DecodeResult {
  match byte {
    b'\x00' => decoded_key(1, Char(' '), modifiers=mod_ctrl)
    b'\x08' => decoded_key(1, Char('h'), modifiers=mod_ctrl)
    b'\t' => decoded_key(1, Tab)
    b'\n' => decoded_key(1, Char('j'), modifiers=mod_ctrl)
    b'\r' => decoded_key(1, Enter)
    b'\x7f' => decoded_key(1, Backspace)
    _ => {
      let n = byte.to_int()
      if n >= 0x01 && n <= 0x1A {
        decoded_key(1, Char((n + 0x60).unsafe_to_char()), modifiers=mod_ctrl)
      } else if n >= 0x1C && n <= 0x1F {
        decoded_key(1, Char((n + 0x40).unsafe_to_char()), modifiers=mod_ctrl)
      } else {
        unknown(bytes, 1)
      }
    }
  }
}

///|
fn with_alt(result : DecodeResult) -> DecodeResult {
  match result {
    Decoded(consumed, Key(event)) =>
      Decoded(
        consumed + 1,
        Key({
          code: event.code,
          modifiers: event.modifiers.union(mod_alt),
          text: "",
        }),
      )
    Decoded(consumed, _) => Decoded(consumed + 1, Key(KeyEvent::new(Escape)))
    NeedMore => NeedMore
  }
}

///|
fn parse_params(bytes : Bytes, start : Int, end : Int) -> Array[Int]? {
  let params : Array[Int] = []
  if start == end {
    return Some(params)
  }
  let mut value = 0
  let mut has_digit = false
  for i in start..<end {
    let byte = bytes[i]
    if is_digit(byte) {
      value = value * 10 + byte.to_int() - b'0'.to_int()
      has_digit = true
    } else if byte == b';' {
      params.push(if has_digit { value } else { -1 })
      value = 0
      has_digit = false
    } else {
      return None
    }
  }
  params.push(if has_digit { value } else { -1 })
  Some(params)
}

///|
fn param(params : Array[Int], index : Int, default : Int) -> Int {
  match params.get(index) {
    Some(value) => if value >= 0 { value } else { default }
    None => default
  }
}

///|
fn xterm_modifiers(value : Int) -> KeyModifiers {
  let mask = if value > 0 { value - 1 } else { 0 }
  let mut modifiers = no_modifiers
  if (mask & 1) != 0 {
    modifiers = modifiers.union(mod_shift)
  }
  if (mask & 2) != 0 {
    modifiers = modifiers.union(mod_alt)
  }
  if (mask & 4) != 0 {
    modifiers = modifiers.union(mod_ctrl)
  }
  if (mask & 8) != 0 {
    modifiers = modifiers.union(mod_meta)
  }
  modifiers
}

///|
fn csi_final(byte : Byte) -> Bool {
  let n = byte.to_int()
  n >= 0x40 && n <= 0x7E
}

///|
fn csi_arrow_or_function(final_byte : Byte) -> KeyCode? {
  match final_byte {
    b'A' => Some(Up)
    b'B' => Some(Down)
    b'C' => Some(Right)
    b'D' => Some(Left)
    b'H' => Some(Home)
    b'F' => Some(End)
    b'P' => Some(F(1))
    b'Q' => Some(F(2))
    b'R' => Some(F(3))
    b'S' => Some(F(4))
    _ => None
  }
}

///|
fn tilde_key(code : Int) -> KeyCode? {
  match code {
    1 | 7 => Some(Home)
    2 => Some(Insert)
    3 => Some(Delete)
    4 | 8 => Some(End)
    5 => Some(PageUp)
    6 => Some(PageDown)
    11..=15 => Some(F(code - 10))
    17..=21 => Some(F(code - 11))
    23..=24 => Some(F(code - 12))
    _ => None
  }
}

///|
fn parse_csi(bytes : Bytes, more : Bool) -> DecodeResult {
  let len = bytes.length()
  guard len > 2 else {
    return if more { NeedMore } else { unknown(bytes, len) }
  }
  let mut final_index = 2
  while final_index < len && !csi_final(bytes[final_index]) {
    final_index = final_index + 1
  }
  guard final_index < len else {
    return if more { NeedMore } else { unknown(bytes, len) }
  }
  let final_byte = bytes[final_index]
  let consumed = final_index + 1
  let params = match parse_params(bytes, 2, final_index) {
    Some(params) => params
    None => return unknown(bytes, consumed)
  }
  match final_byte {
    b'Z' => decoded_key(consumed, Tab, modifiers=mod_shift)
    b'~' => {
      let code = param(params, 0, -1)
      match tilde_key(code) {
        Some(key) => {
          let modifiers = xterm_modifiers(param(params, 1, 1))
          decoded_key(consumed, key, modifiers~)
        }
        None => unknown(bytes, consumed)
      }
    }
    _ =>
      match csi_arrow_or_function(final_byte) {
        Some(key) => {
          let modifiers = if params.length() >= 2 {
            xterm_modifiers(param(params, 1, 1))
          } else if params.length() == 1 {
            xterm_modifiers(param(params, 0, 1))
          } else {
            no_modifiers
          }
          decoded_key(consumed, key, modifiers~)
        }
        None => unknown(bytes, consumed)
      }
  }
}

///|
fn parse_ss3(bytes : Bytes, more : Bool) -> DecodeResult {
  let len = bytes.length()
  guard len > 2 else {
    return if more { NeedMore } else { unknown(bytes, len) }
  }
  match bytes[2] {
    b'A' => decoded_key(3, Up)
    b'B' => decoded_key(3, Down)
    b'C' => decoded_key(3, Right)
    b'D' => decoded_key(3, Left)
    b'H' => decoded_key(3, Home)
    b'F' => decoded_key(3, End)
    b'P' => decoded_key(3, F(1))
    b'Q' => decoded_key(3, F(2))
    b'R' => decoded_key(3, F(3))
    b'S' => decoded_key(3, F(4))
    _ => unknown(bytes, 3)
  }
}

///|
pub fn decode_one(bytes : Bytes, more? : Bool = true) -> DecodeResult {
  guard !bytes.is_empty() else { return NeedMore }
  let byte = bytes[0]
  if byte == Esc {
    if bytes.length() == 1 {
      return if more { NeedMore } else { decoded_key(1, Escape) }
    }
    match bytes[1] {
      b'[' => parse_csi(bytes, more)
      b'O' => parse_ss3(bytes, more)
      _ => with_alt(decode_one(bytes.view(start=1).to_owned(), more~))
    }
  } else if byte <= b'\x1f' || byte == b'\x7f' {
    control_key(bytes, byte)
  } else if byte < b'\x80' {
    let char = byte.to_char()
    decoded_key(1, Char(char), text=char_text(char))
  } else {
    parse_utf8(bytes, more)
  }
}
