///|
const Esc : Byte = b'\x1b'

///|
const EventReaderInitialBufferCapacity : Int = 8

///|
/// Low-level terminal byte stream decoder.
///
/// Use this directly when decoding an arbitrary `@io.Reader`. Terminal callers
/// that own a `Tty` should usually prefer `Tty::read_event`.
struct EventReader {
  reader : &@io.Reader
  mut data : FixedArray[Byte]
  mut head : Int
  mut read : Int
  mut tail : Int
}

///|
/// Create an event reader over an async byte reader.
pub fn EventReader::new(reader : &@io.Reader) -> EventReader {
  EventReader::{
    reader,
    data: FixedArray::make(EventReaderInitialBufferCapacity, b'\x00'),
    head: 0,
    read: 0,
    tail: 0,
  }
}

///|
/// Read one terminal stream event.
///
/// `esc_timeout_ms` is the short wait used after an event has started to
/// disambiguate standalone Esc and incomplete multi-byte sequences.
pub async fn EventReader::read_event(
  self : EventReader,
  esc_timeout_ms? : Int = 50,
) -> Event {
  let start = self.read
  try {
    let byte = self.read_byte()
    let event = if byte == Esc {
      read_escape(self, esc_timeout_ms)
    } else {
      Input(read_byte_event(self, byte, esc_timeout_ms))
    }
    self.commit()
    event
  } catch {
    err => {
      self.rollback_to(start)
      raise err
    }
  }
}

///|
async fn EventReader::read_byte(self : EventReader) -> Byte {
  if self.read < self.tail {
    let byte = self.data[self.read]
    self.read += 1
    byte
  } else {
    let byte = self.read_byte_raw()
    self.ensure_capacity(1)
    self.data[self.tail] = byte
    self.tail += 1
    self.read += 1
    byte
  }
}

///|
async fn EventReader::read_byte_raw(self : EventReader) -> Byte {
  self.reader.read_exactly(1)[0]
}

///|
fn EventReader::unread_byte(self : EventReader) -> Unit {
  guard self.read > self.head
  self.read -= 1
}

///|
fn EventReader::rollback_to(self : EventReader, read : Int) -> Unit {
  self.read = read
}

///|
fn EventReader::view(self : EventReader) -> BytesView {
  self.data.unsafe_reinterpret_as_bytes()[self.head:self.read]
}

///|
fn EventReader::ensure_capacity(self : EventReader, extra : Int) -> Unit {
  let required = self.tail + extra
  if required <= self.data.length() {
    return
  }
  let mut capacity = self.data.length()
  if capacity == 0 {
    capacity = EventReaderInitialBufferCapacity
  }
  while capacity < required {
    capacity = capacity * 2
  }
  let data = FixedArray::make(capacity, b'\x00')
  if self.tail > 0 {
    self.data.blit_to(data, len=self.tail)
  }
  self.data = data
}

///|
fn EventReader::commit(self : EventReader) -> Unit {
  if self.read == self.tail {
    self.head = 0
    self.read = 0
    self.tail = 0
  } else {
    let remaining = self.tail - self.read
    if remaining > 0 {
      self.data.blit_to(self.data, len=remaining, src_offset=self.read)
    }
    self.head = 0
    self.read = 0
    self.tail = remaining
  }
}

///|
async fn read_escape(reader : EventReader, esc_timeout_ms : Int) -> Event {
  guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
    is Some(byte) else {
    Input(Key(KeyEvent::new(Escape)))
  }
  match byte {
    Esc => {
      reader.unread_byte()
      Input(Key(KeyEvent::new(Escape)))
    }
    b'[' => read_csi(reader, esc_timeout_ms~)
    b'O' => Input(read_ss3(reader, esc_timeout_ms~))
    0x20..<0x7f as byte =>
      Input(
        Key(
          KeyEvent::new(
            Char(byte.to_char()),
            modifiers=KeyModifiers::new(alt=true),
          ),
        ),
      )
    _ => Input(Unknown(reader.view().to_owned()))
  }
}

///|
async fn read_ss3(reader : EventReader, esc_timeout_ms~ : Int) -> InputEvent {
  guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
    is Some(byte) else {
    return Unknown(reader.view().to_owned())
  }
  if byte == Esc {
    reader.unread_byte()
    return Unknown(reader.view().to_owned())
  }
  ss3_event(reader.view())
}

///|
async fn read_csi(reader : EventReader, esc_timeout_ms~ : Int) -> Event {
  let mut seen_intermediate = false
  for ;; {
    guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
      is Some(byte) else {
      return match reader.view() {
        [Esc, b'['] =>
          Input(
            Key(KeyEvent::new(Char('['), modifiers=KeyModifiers::new(alt=true))),
          )
        _ => Input(Unknown(reader.view().to_owned()))
      }
    }
    match byte {
      0x30..<0x40 if seen_intermediate =>
        break Input(Unknown(reader.view().to_owned()))
      0x30..<0x40 => ()
      0x20..<0x30 => seen_intermediate = true
      0x40..<0x7f =>
        break if is_bracketed_paste_start(reader.view()) {
          read_bracketed_paste(reader, esc_timeout_ms~)
        } else {
          parse_csi(reader.view())
        }
      _ => break Input(Unknown(reader.view().to_owned()))
    }
  }
}

///|
fn is_bracketed_paste_start(csi : BytesView) -> Bool {
  match csi {
    [Esc, .. b"[200~"] => true
    _ => false
  }
}

///|
async fn read_bracketed_paste(
  reader : EventReader,
  esc_timeout_ms~ : Int,
) -> Event {
  for ;; {
    guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
      is Some(_) else {
      return Input(Unknown(reader.view().to_owned()))
    }
    let view = reader.view()
    if parse_bracketed_paste(view) is Some(event) {
      return event
    }
  }
}

///|
fn parse_bracketed_paste(paste : BytesView) -> Event? {
  match paste {
    [Esc, .. b"[200~", .. payload, Esc, .. b"[201~"] =>
      Some(
        try @utf8.decode(payload) catch {
          _ => Input(Unknown(paste.to_owned()))
        } noraise {
          text => Input(Paste(text))
        },
      )
    _ => None
  }
}

///|
fn ss3_event(ss3 : BytesView) -> InputEvent {
  match ss3 {
    [Esc, b'O', b'A'] => Key(KeyEvent::new(Up))
    [Esc, b'O', b'B'] => Key(KeyEvent::new(Down))
    [Esc, b'O', b'C'] => Key(KeyEvent::new(Right))
    [Esc, b'O', b'D'] => Key(KeyEvent::new(Left))
    [Esc, b'O', b'H'] => Key(KeyEvent::new(Home))
    [Esc, b'O', b'F'] => Key(KeyEvent::new(End))
    [Esc, b'O', b'P'] => Key(KeyEvent::new(F1))
    [Esc, b'O', b'Q'] => Key(KeyEvent::new(F2))
    [Esc, b'O', b'R'] => Key(KeyEvent::new(F3))
    [Esc, b'O', b'S'] => Key(KeyEvent::new(F4))
    _ => Unknown(ss3.to_owned())
  }
}

///|
fn parse_csi(csi : BytesView) -> Event {
  match csi {
    [Esc, b'[', b'Z'] =>
      Input(Key(KeyEvent::new(Tab, modifiers=KeyModifiers::new(shift=true))))
    [Esc, b'[', .. params, b'~'] => {
      guard parse_csi_params(params) is Some(params) else {
        return Input(Unknown(csi.to_owned()))
      }
      Input(parse_csi_tilde_key(csi, params))
    }
    [Esc, b'[', .. params, final_byte] => {
      guard parse_csi_params(params) is Some(params) else {
        return Input(Unknown(csi.to_owned()))
      }
      match final_byte {
        b'A' => Input(parse_csi_key(csi, params, Up))
        b'B' => Input(parse_csi_key(csi, params, Down))
        b'C' => Input(parse_csi_key(csi, params, Right))
        b'D' => Input(parse_csi_key(csi, params, Left))
        b'H' => Input(parse_csi_key(csi, params, Home))
        b'F' => Input(parse_csi_key(csi, params, End))
        b'P' => Input(parse_csi_key(csi, params, F1))
        b'Q' => Input(parse_csi_key(csi, params, F2))
        b'R' if parse_cursor_position_params(params) is Some((row, col)) =>
          CursorPosition(row~, col~)
        b'R' => Input(parse_csi_key(csi, params, F3))
        b'S' => Input(parse_csi_key(csi, params, F4))
        _ => Input(Unknown(csi.to_owned()))
      }
    }
    _ => Input(Unknown(csi.to_owned()))
  }
}

///|
fn parse_cursor_position_params(params : Array[Int?]) -> (Int, Int)? {
  match params {
    [Some(row), Some(col)] if row >= 1 && col >= 1 => Some((row, col))
    _ => None
  }
}

///|
fn parse_csi_key(
  csi : BytesView,
  params : Array[Int?],
  code : KeyCode,
) -> InputEvent {
  guard parse_csi_key_modifiers(params) is Some(modifiers) else {
    return Unknown(csi.to_owned())
  }
  Key(KeyEvent::new(code, modifiers~))
}

///|
fn parse_csi_params(params_bytes : BytesView) -> Array[Int?]? {
  let params : Array[Int?] = []
  if params_bytes.length() == 0 {
    return Some(params)
  }
  let mut value = 0
  let mut seen = false
  for i = 0; i < params_bytes.length(); {
    let byte = params_bytes[i]
    match byte {
      b'0'..=b'9' => {
        seen = true
        value = value * 10 + byte.to_int() - b'0'.to_int()
        continue i + 1
      }
      b';' => {
        params.push(if seen { Some(value) } else { None })
        value = 0
        seen = false
        continue i + 1
      }
      _ => return None
    }
  }
  params.push(if seen { Some(value) } else { None })
  Some(params)
}

///|
fn parse_csi_key_modifiers(params : Array[Int?]) -> KeyModifiers? {
  match params {
    [] | [None | Some(1)] | [None | Some(1), None] => Some(KeyModifiers::new())
    [None | Some(1), Some(modifier)] => Some(modifiers_from_param(modifier))
    _ => None
  }
}

///|
fn parse_csi_tilde_key(csi : BytesView, params : Array[Int?]) -> InputEvent {
  let (code, modifiers) = match params {
    [Some(code)] => (code, KeyModifiers::new())
    [Some(code), None] => (code, KeyModifiers::new())
    [Some(code), Some(modifier)] => (code, modifiers_from_param(modifier))
    _ => return Unknown(csi.to_owned())
  }
  guard tilde_key_code(code) is Some(key_code) else {
    return Unknown(csi.to_owned())
  }
  Key(KeyEvent::new(key_code, modifiers~))
}

///|
fn tilde_key_code(code : Int) -> KeyCode? {
  match code {
    1 | 7 => Some(Home)
    2 => Some(Insert)
    3 => Some(Delete)
    4 | 8 => Some(End)
    5 => Some(PageUp)
    6 => Some(PageDown)
    11 => Some(F1)
    12 => Some(F2)
    13 => Some(F3)
    14 => Some(F4)
    15 => Some(F5)
    17 => Some(F6)
    18 => Some(F7)
    19 => Some(F8)
    20 => Some(F9)
    21 => Some(F10)
    23 => Some(F11)
    24 => Some(F12)
    _ => None
  }
}

///|
fn modifiers_from_param(param : Int) -> KeyModifiers {
  let bits = param - 1
  if bits <= 0 {
    KeyModifiers::new()
  } else {
    KeyModifiers::new(
      shift=(bits & 1) != 0,
      alt=(bits & 2) != 0,
      ctrl=(bits & 4) != 0,
      meta=(bits & 8) != 0,
    )
  }
}

///|
async fn read_byte_event(
  reader : EventReader,
  byte : Byte,
  esc_timeout_ms : Int,
) -> InputEvent {
  match byte {
    b'\r' => Key(KeyEvent::new(Enter))
    b'\n' =>
      Key(KeyEvent::new(Char('j'), modifiers=KeyModifiers::new(ctrl=true)))
    b'\t' => Key(KeyEvent::new(Tab))
    b'\x7f' | b'\x08' => Key(KeyEvent::new(Backspace))
    b'\x00' =>
      Key(KeyEvent::new(Char(' '), modifiers=KeyModifiers::new(ctrl=true)))
    0x01..=0x1a =>
      Key(
        KeyEvent::new(
          Char((byte.to_int() - 1 + 'a'.to_int()).unsafe_to_char()),
          modifiers=KeyModifiers::new(ctrl=true),
        ),
      )
    0x1c..=0x1f =>
      Key(
        KeyEvent::new(
          Char((byte.to_int() - 0x1c + '4'.to_int()).unsafe_to_char()),
          modifiers=KeyModifiers::new(ctrl=true),
        ),
      )
    0x20..<0x7f => {
      let char = byte.to_char()
      Key(KeyEvent::new(Char(char), text=[char]))
    }
    _ => read_utf8_text(reader, byte, esc_timeout_ms~)
  }
}

///|
async fn read_utf8_text(
  reader : EventReader,
  first : Byte,
  esc_timeout_ms~ : Int,
) -> InputEvent {
  guard utf8_sequence_length(first) is Some(len) else {
    return Unknown([first])
  }
  for _ in 1..<len {
    guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
      is Some(byte) else {
      return Unknown(reader.view().to_owned())
    }
    if !is_utf8_continuation(byte) {
      reader.unread_byte()
      return Unknown(reader.view().to_owned())
    }
  }
  let bytes = reader.view().to_owned()
  try @utf8.decode(bytes) catch {
    _ => Unknown(bytes)
  } noraise {
    text => text_event(text)
  }
}

///|
fn text_event(text : String) -> InputEvent {
  let mut count = 0
  let mut first = '\u{0}'
  for ch in text {
    if count == 0 {
      first = ch
    }
    count += 1
  }
  if count == 1 {
    Key(KeyEvent::new(Char(first), text~))
  } else {
    Key(KeyEvent::new(Text, text~))
  }
}

///|
fn utf8_sequence_length(first : Byte) -> Int? {
  match first {
    0xc2..=0xdf => Some(2)
    0xe0..=0xef => Some(3)
    0xf0..=0xf4 => Some(4)
    _ => None
  }
}

///|
fn is_utf8_continuation(byte : Byte) -> Bool {
  byte >= b'\x80' && byte <= b'\xbf'
}
