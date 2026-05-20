///|
const Esc : Byte = b'\x1b'

///|
const EventReaderBufferSize : Int = 8

///|
struct EventReader {
  reader : &@io.Reader
  data : FixedArray[Byte]
  mut head : Int
  mut tail : Int
}

///|
pub fn EventReader::new(reader : &@io.Reader) -> EventReader {
  EventReader::{
    reader,
    data: FixedArray::make(EventReaderBufferSize, b'\x00'),
    head: 0,
    tail: 0,
  }
}

///|
pub async fn EventReader::read_event(
  self : EventReader,
  esc_timeout? : Int = 50,
) -> Event {
  guard self.read_byte() is Some(byte) else { abort("unreachable") }
  if byte == Esc {
    let buffer = @buffer.new()
    buffer.write_byte(Esc)
    read_escape(self, buffer, esc_timeout)
  } else {
    byte_event(byte)
  }
}

///|
async fn EventReader::read_byte(self : EventReader, timeout? : Int) -> Byte? {
  if self.head < self.tail {
    let byte = self.data[self.head]
    self.head += 1
    if self.head == self.tail {
      self.head = 0
      self.tail = 0
    }
    Some(byte)
  } else {
    match timeout {
      Some(timeout) =>
        @async.with_timeout_opt(timeout, () => self.read_byte_raw())
      None => Some(self.read_byte_raw())
    }
  }
}

///|
async fn EventReader::read_byte_raw(self : EventReader) -> Byte {
  self.reader.read_exactly(1)[0]
}

///|
fn EventReader::unread_byte(self : EventReader, byte : Byte) -> Unit {
  if self.tail == self.data.length() {
    let len = self.tail - self.head
    if self.head > 0 {
      self.data.blit_to(self.data, src_offset=self.head, len~)
      self.head = 0
      self.tail = len
    }
  }
  guard self.tail < self.data.length()
  self.data[self.tail] = byte
  self.tail += 1
}

///|
async fn read_escape(
  reader : EventReader,
  buffer : @buffer.Buffer,
  esc_timeout : Int,
) -> Event {
  guard reader.read_byte(timeout=esc_timeout) is Some(byte) else {
    Key(KeyEvent::new(Escape))
  }
  match byte {
    Esc => {
      reader.unread_byte(byte)
      Key(KeyEvent::new(Escape))
    }
    _ => {
      buffer.write_byte(byte)
      read_escape_tail(reader, buffer, byte, esc_timeout)
    }
  }
}

///|
async fn read_escape_tail(
  reader : EventReader,
  buffer : @buffer.Buffer,
  byte : Byte,
  esc_timeout : Int,
) -> Event {
  match byte {
    b'[' => read_csi(reader, buffer, esc_timeout~)
    b'O' => read_ss3(reader, buffer, esc_timeout~)
    0x20..<0x7f as byte =>
      Key(
        KeyEvent::new(
          Char(byte.to_char()),
          modifiers=KeyModifiers::new(alt=true),
        ),
      )
    byte => Unknown([Esc, byte])
  }
}

///|
async fn read_ss3(
  reader : EventReader,
  buffer : @buffer.Buffer,
  esc_timeout~ : Int,
) -> Event {
  guard reader.read_byte(timeout=esc_timeout) is Some(byte) else {
    return Unknown(buffer.to_bytes())
  }
  if byte == Esc {
    reader.unread_byte(byte)
    return Unknown(buffer.to_bytes())
  }
  buffer.write_byte(byte)
  ss3_event(buffer.to_bytes())
}

///|
async fn read_csi(
  reader : EventReader,
  buffer : @buffer.Buffer,
  esc_timeout~ : Int,
) -> Event {
  let mut seen_intermediate = false
  for ;; {
    guard reader.read_byte(timeout=esc_timeout) is Some(byte) else {
      let bytes = buffer.to_bytes()
      return match bytes {
        [Esc, b'['] =>
          Key(KeyEvent::new(Char('['), modifiers=KeyModifiers::new(alt=true)))
        _ => Unknown(bytes)
      }
    }
    buffer.write_byte(byte)
    match byte {
      0x30..<0x40 if seen_intermediate => break Unknown(buffer.to_bytes())
      0x30..<0x40 => ()
      0x20..<0x30 => seen_intermediate = true
      0x40..<0x7f => break parse_csi(buffer.to_bytes())
      _ => break Unknown(buffer.to_bytes())
    }
  }
}

///|
fn ss3_event(ss3 : Bytes) -> Event {
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
    _ => Unknown(ss3)
  }
}

///|
fn parse_csi(csi : Bytes) -> Event {
  match csi {
    [Esc, b'[', b'Z'] =>
      Key(KeyEvent::new(Tab, modifiers=KeyModifiers::new(shift=true)))
    [Esc, b'[', .. params, b'~'] => {
      guard parse_csi_params(params) is Some(params) else {
        return Unknown(csi)
      }
      parse_csi_tilde_key(csi, params)
    }
    [Esc, b'[', .. params, final_byte] => {
      guard parse_csi_params(params) is Some(params) else {
        return Unknown(csi)
      }
      match final_byte {
        b'A' => parse_csi_key(csi, params, Up)
        b'B' => parse_csi_key(csi, params, Down)
        b'C' => parse_csi_key(csi, params, Right)
        b'D' => parse_csi_key(csi, params, Left)
        b'H' => parse_csi_key(csi, params, Home)
        b'F' => parse_csi_key(csi, params, End)
        b'P' => parse_csi_key(csi, params, F1)
        b'Q' => parse_csi_key(csi, params, F2)
        b'R' => parse_csi_key(csi, params, F3)
        b'S' => parse_csi_key(csi, params, F4)
        _ => Unknown(csi)
      }
    }
    _ => Unknown(csi)
  }
}

///|
fn parse_csi_key(csi : Bytes, params : Array[Int?], code : KeyCode) -> Event {
  guard parse_csi_key_modifiers(params) is Some(modifiers) else {
    return Unknown(csi)
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
fn parse_csi_tilde_key(csi : Bytes, params : Array[Int?]) -> Event {
  let (code, modifiers) = match params {
    [Some(code)] => (code, KeyModifiers::new())
    [Some(code), None] => (code, KeyModifiers::new())
    [Some(code), Some(modifier)] => (code, modifiers_from_param(modifier))
    _ => return Unknown(csi)
  }
  guard tilde_key_code(code) is Some(key_code) else { return Unknown(csi) }
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
fn byte_event(byte : Byte) -> Event {
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
    _ => Unknown([byte])
  }
}
