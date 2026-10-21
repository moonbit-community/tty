///|
/// SGR mouse button codes (xterm 1006).
const SgrLeftButton : Int32 = 0

///|
const SgrMiddleButton : Int32 = 1

///|
const SgrRightButton : Int32 = 2

///|
const SgrNoButton : Int32 = 3

///|
const SgrShift : Int32 = 4

///|
const SgrAlt : Int32 = 8

///|
const SgrCtrl : Int32 = 16

///|
const SgrMotion : Int32 = 32

///|
const SgrWheel : Int32 = 64

///|
/// Serializes Win32 console input records into VT input bytes.
///
/// Every record kind becomes the sequence a VT terminal would send for it, so
/// one byte decoder handles console input in record order:
///
/// - key records become their UTF-8 text when the console has VT input
///   enabled, and win32-input-mode reports (`CSI Vk;Sc;Uc;Kd;Cs;Rc _`)
///   otherwise
/// - mouse records become SGR mouse reports (`CSI < Cb;col;row M/m`)
/// - focus records become focus reports (`CSI I` / `CSI O`)
///
/// Window buffer size records produce no bytes: resize is out-of-band, as
/// `SIGWINCH` is on Unix, and `ConsoleReader` reports it separately.
///
/// The encoder keeps the state that spans records: a pending UTF-16 high
/// surrogate, and the mouse buttons held at the previous mouse record.
priv struct RecordEncoder {
  mut high_surrogate : Int32?
  mut mouse_buttons : Int32
}

///|
fn RecordEncoder::new() -> RecordEncoder {
  { high_surrogate: None, mouse_buttons: 0, }
}

///|
fn RecordEncoder::encode(
  self : RecordEncoder,
  record : InputRecord,
  vt_input~ : Bool,
  out : @buffer.Buffer,
) -> Unit {
  match record {
    Key(key) => self.encode_key(key, vt_input~, out)
    Mouse(mouse) => {
      self.high_surrogate = None
      self.encode_mouse(mouse, out)
    }
    Focus(focus_set) => {
      self.high_surrogate = None
      out.write_bytes(if focus_set { b"\x1b[I" } else { b"\x1b[O" })
    }
    WindowBufferSize(_) | Unsupported(_) => self.high_surrogate = None
  }
}

///|
/// Key-up records are dropped: terminals without the kitty keyboard protocol
/// report presses only. A coalesced `repeat_count` is expanded into that many
/// copies of the key.
fn RecordEncoder::encode_key(
  self : RecordEncoder,
  record : KeyRecord,
  vt_input~ : Bool,
  out : @buffer.Buffer,
) -> Unit {
  guard record.key_down != 0 else { return }
  let repeat_count = if record.repeat_count > 0 {
    record.repeat_count
  } else {
    1
  }
  if vt_input ||
    record.virtual_key_code == 0 ||
    is_surrogate(record.unicode_char) {
    // With VT input the console already translated keys into VT text. Records
    // without a virtual key carry synthesized text such as IME output.
    guard self.text_char(record.unicode_char) is Some(char) else { return }
    for _ in 0..<repeat_count {
      out.write_char_utf8(char)
    }
  } else if record.unicode_char == 0 &&
    is_lone_modifier_key(record.virtual_key_code) {
    ()
  } else {
    self.high_surrogate = None
    let ControlKeyState(control_key_state) = record.control_key_state
    let report = "\u{1b}[\{record.virtual_key_code};\{record.virtual_scan_code};\{record.unicode_char};1;\{control_key_state};\{repeat_count}_"
    for _ in 0..<repeat_count {
      out.write_string_utf8(report)
    }
  }
}

///|
/// Decode one UTF-16 code unit from a key record, joining surrogate pairs that
/// Windows splits across two records.
fn RecordEncoder::text_char(self : RecordEncoder, unit : Int32) -> Char? {
  match unit {
    0 => {
      self.high_surrogate = None
      None
    }
    0xd800..<=0xdbff => {
      self.high_surrogate = Some(unit)
      None
    }
    0xdc00..<=0xdfff => {
      let high = self.high_surrogate
      self.high_surrogate = None
      guard high is Some(high) else { return None }
      (0x10000 + (high - 0xd800) * 0x400 + (unit - 0xdc00)).to_char()
    }
    _ => {
      self.high_surrogate = None
      unit.to_char()
    }
  }
}

///|
fn is_surrogate(unit : Int32) -> Bool {
  unit >= 0xd800 && unit <= 0xdfff
}

///|
/// Modifier and lock keys produce no input on their own in a terminal.
fn is_lone_modifier_key(vk : Int32) -> Bool {
  match vk {
    // VK_SHIFT, VK_CONTROL, VK_MENU, VK_CAPITAL
    0x10 | 0x11 | 0x12 | 0x14 => true
    // VK_LWIN, VK_RWIN
    0x5b | 0x5c => true
    // VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU
    0xa0..<=0xa5 => true
    _ => false
  }
}

///|
/// Console mouse coordinates are 0-based; SGR reports are 1-based.
fn RecordEncoder::encode_mouse(
  self : RecordEncoder,
  record : MouseRecord,
  out : @buffer.Buffer,
) -> Unit {
  guard self.mouse_report(record) is Some((button, release)) else { return }
  let cb = button | sgr_modifiers(record.control_key_state)
  out.write_string_utf8("\u{1b}[<\{cb};\{record.x + 1};\{record.y + 1}")
  out.write_char_utf8(if release { 'm' } else { 'M' })
}

///|
/// Pick the SGR button code for a console mouse record, and whether it is a
/// release. A plain record reports the button whose state changed since the
/// previous record.
fn RecordEncoder::mouse_report(
  self : RecordEncoder,
  record : MouseRecord,
) -> (Int32, Bool)? {
  let buttons = record.button_state & MouseButtonMask
  let previous = self.mouse_buttons
  self.mouse_buttons = buttons
  match record.event_flags {
    0 =>
      if sgr_button(buttons & (previous ^ buttons)) is Some(pressed) {
        Some((pressed, false))
      } else if sgr_button(previous & (previous ^ buttons)) is Some(released) {
        Some((released, true))
      } else {
        None
      }
    MouseMoved =>
      match sgr_button(buttons) {
        Some(button) => Some((SgrMotion | button, false))
        None => Some((SgrMotion | SgrNoButton, false))
      }
    MouseDoubleClick => sgr_button(buttons).map(button => (button, false))
    MouseWheeled =>
      match signed_high_word(record.button_state) {
        0 => None
        delta if delta > 0 => Some((SgrWheel | 0, false))
        _ => Some((SgrWheel | 1, false))
      }
    MouseHorizontalWheeled =>
      match signed_high_word(record.button_state) {
        0 => None
        delta if delta > 0 => Some((SgrWheel | 3, false))
        _ => Some((SgrWheel | 2, false))
      }
    _ => None
  }
}

///|
fn sgr_button(buttons : Int32) -> Int32? {
  if (buttons & MouseLeftButton) != 0 {
    Some(SgrLeftButton)
  } else if (buttons & MouseMiddleButton) != 0 {
    Some(SgrMiddleButton)
  } else if (buttons & MouseRightButton) != 0 {
    Some(SgrRightButton)
  } else {
    None
  }
}

///|
fn sgr_modifiers(state : ControlKeyState) -> Int32 {
  let mut bits = 0
  if state.has_state(ShiftPressed) {
    bits = bits | SgrShift
  }
  if state.has_state(LeftAltPressed | RightAltPressed) {
    bits = bits | SgrAlt
  }
  if state.has_state(LeftCtrlPressed | RightCtrlPressed) {
    bits = bits | SgrCtrl
  }
  bits
}

///|
/// Wheel records carry the signed wheel delta in the high word of
/// `dwButtonState`.
fn signed_high_word(value : Int32) -> Int32 {
  let low_word = value & 0xffff
  (value - low_word) / 0x10000
}
