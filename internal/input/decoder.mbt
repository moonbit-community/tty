///|
const Esc : Byte = b'\x1b'

///|
const EventReaderInitialBufferCapacity : Int = 8

///|
/// Internal low-level terminal byte stream decoder.
///
/// Root `Tty` uses this to coordinate user input with terminal response
/// traffic.
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
    Input(@public_input.Key(@public_input.KeyEvent::new(@public_input.Escape)))
  }
  match byte {
    Esc => {
      reader.unread_byte()
      Input(
        @public_input.Key(@public_input.KeyEvent::new(@public_input.Escape)),
      )
    }
    b'[' => read_csi(reader, esc_timeout_ms~)
    b'O' => Input(read_ss3(reader, esc_timeout_ms~))
    0x20..<0x7f as byte =>
      Input(
        @public_input.Key(
          @public_input.KeyEvent::new(
            @public_input.Char(byte.to_char()),
            modifiers=@public_input.KeyModifiers::new(alt=true),
          ),
        ),
      )
    _ => Input(@public_input.Unknown(reader.view().to_owned()))
  }
}

///|
async fn read_ss3(
  reader : EventReader,
  esc_timeout_ms~ : Int,
) -> @public_input.InputEvent {
  guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
    is Some(byte) else {
    return @public_input.Unknown(reader.view().to_owned())
  }
  if byte == Esc {
    reader.unread_byte()
    return @public_input.Unknown(reader.view().to_owned())
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
            @public_input.Key(
              @public_input.KeyEvent::new(
                @public_input.Char('['),
                modifiers=@public_input.KeyModifiers::new(alt=true),
              ),
            ),
          )
        _ => Input(@public_input.Unknown(reader.view().to_owned()))
      }
    }
    match byte {
      0x30..<0x40 if seen_intermediate =>
        break Input(@public_input.Unknown(reader.view().to_owned()))
      0x30..<0x40 => ()
      0x20..<0x30 => seen_intermediate = true
      0x40..<0x7f =>
        break if is_bracketed_paste_start(reader.view()) {
          read_bracketed_paste(reader, esc_timeout_ms~)
        } else {
          parse_csi(reader.view())
        }
      _ => break Input(@public_input.Unknown(reader.view().to_owned()))
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
      return Input(@public_input.Unknown(reader.view().to_owned()))
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
          _ => Input(@public_input.Unknown(paste.to_owned()))
        } noraise {
          text => Input(@public_input.Paste(text))
        },
      )
    _ => None
  }
}

///|
fn ss3_event(ss3 : BytesView) -> @public_input.InputEvent {
  match ss3 {
    [Esc, b'O', b'A'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Up))
    [Esc, b'O', b'B'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Down))
    [Esc, b'O', b'C'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Right))
    [Esc, b'O', b'D'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Left))
    [Esc, b'O', b'H'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Home))
    [Esc, b'O', b'F'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.End))
    [Esc, b'O', b'P'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.F1))
    [Esc, b'O', b'Q'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.F2))
    [Esc, b'O', b'R'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.F3))
    [Esc, b'O', b'S'] =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.F4))
    _ => @public_input.Unknown(ss3.to_owned())
  }
}

///|
fn parse_csi(csi : BytesView) -> Event {
  match csi {
    [Esc, b'[', b'?', .. params, b'u'] =>
      parse_keyboard_enhancement_flags(csi, params)
    [Esc, b'[', b'?', .. params, b'c'] =>
      parse_primary_device_attributes(csi, params)
    [Esc, b'[', b'Z'] =>
      Input(
        @public_input.Key(
          @public_input.KeyEvent::new(
            @public_input.Tab,
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      )
    [Esc, b'[', .. params, b'~'] => {
      guard parse_csi_params(params) is Some(params) else {
        return Input(@public_input.Unknown(csi.to_owned()))
      }
      Input(parse_csi_tilde_key(csi, params))
    }
    [Esc, b'[', .. params, final_byte] => {
      guard parse_csi_params(params) is Some(params) else {
        return Input(@public_input.Unknown(csi.to_owned()))
      }
      match final_byte {
        b'A' => Input(parse_csi_key(csi, params, @public_input.Up))
        b'B' => Input(parse_csi_key(csi, params, @public_input.Down))
        b'C' => Input(parse_csi_key(csi, params, @public_input.Right))
        b'D' => Input(parse_csi_key(csi, params, @public_input.Left))
        b'H' => Input(parse_csi_key(csi, params, @public_input.Home))
        b'F' => Input(parse_csi_key(csi, params, @public_input.End))
        b'P' => Input(parse_csi_key(csi, params, @public_input.F1))
        b'Q' => Input(parse_csi_key(csi, params, @public_input.F2))
        b'R' if parse_cursor_position_params(params) is Some((row, col)) =>
          CursorPosition(row~, col~)
        b'R' => Input(parse_csi_key(csi, params, @public_input.F3))
        b'S' => Input(parse_csi_key(csi, params, @public_input.F4))
        _ => Input(@public_input.Unknown(csi.to_owned()))
      }
    }
    _ => Input(@public_input.Unknown(csi.to_owned()))
  }
}

///|
fn parse_keyboard_enhancement_flags(
  csi : BytesView,
  params : BytesView,
) -> Event {
  guard parse_decimal_param(params) is Some(flags) else {
    return Input(@public_input.Unknown(csi.to_owned()))
  }
  KeyboardEnhancementFlags(flags)
}

///|
fn parse_primary_device_attributes(
  csi : BytesView,
  params : BytesView,
) -> Event {
  if is_primary_device_attributes_params(params) {
    PrimaryDeviceAttributes(csi.to_owned())
  } else {
    Input(@public_input.Unknown(csi.to_owned()))
  }
}

///|
fn parse_decimal_param(params : BytesView) -> Int? {
  guard params.length() > 0 else { return None }
  let mut value = 0
  for i = 0; i < params.length(); {
    let byte = params[i]
    match byte {
      b'0'..=b'9' => {
        value = value * 10 + byte.to_int() - b'0'.to_int()
        continue i + 1
      }
      _ => return None
    }
  }
  Some(value)
}

///|
fn is_primary_device_attributes_params(params : BytesView) -> Bool {
  guard params.length() > 0 else { return false }
  let mut part_has_digit = false
  for i = 0; i < params.length(); {
    let byte = params[i]
    match byte {
      b'0'..=b'9' => {
        part_has_digit = true
        continue i + 1
      }
      b';' if part_has_digit => {
        part_has_digit = false
        continue i + 1
      }
      _ => return false
    }
  }
  part_has_digit
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
  code : @public_input.KeyCode,
) -> @public_input.InputEvent {
  guard parse_csi_key_modifiers(params) is Some(modifiers) else {
    return @public_input.Unknown(csi.to_owned())
  }
  @public_input.Key(@public_input.KeyEvent::new(code, modifiers~))
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
fn parse_csi_key_modifiers(params : Array[Int?]) -> @public_input.KeyModifiers? {
  match params {
    [] | [None | Some(1)] | [None | Some(1), None] =>
      Some(@public_input.KeyModifiers::new())
    [None | Some(1), Some(modifier)] => Some(modifiers_from_param(modifier))
    _ => None
  }
}

///|
fn parse_csi_tilde_key(
  csi : BytesView,
  params : Array[Int?],
) -> @public_input.InputEvent {
  let (code, modifiers) = match params {
    [Some(code)] => (code, @public_input.KeyModifiers::new())
    [Some(code), None] => (code, @public_input.KeyModifiers::new())
    [Some(code), Some(modifier)] => (code, modifiers_from_param(modifier))
    _ => return @public_input.Unknown(csi.to_owned())
  }
  guard tilde_key_code(code) is Some(key_code) else {
    return @public_input.Unknown(csi.to_owned())
  }
  @public_input.Key(@public_input.KeyEvent::new(key_code, modifiers~))
}

///|
fn tilde_key_code(code : Int) -> @public_input.KeyCode? {
  match code {
    1 | 7 => Some(@public_input.Home)
    2 => Some(@public_input.Insert)
    3 => Some(@public_input.Delete)
    4 | 8 => Some(@public_input.End)
    5 => Some(@public_input.PageUp)
    6 => Some(@public_input.PageDown)
    11 => Some(@public_input.F1)
    12 => Some(@public_input.F2)
    13 => Some(@public_input.F3)
    14 => Some(@public_input.F4)
    15 => Some(@public_input.F5)
    17 => Some(@public_input.F6)
    18 => Some(@public_input.F7)
    19 => Some(@public_input.F8)
    20 => Some(@public_input.F9)
    21 => Some(@public_input.F10)
    23 => Some(@public_input.F11)
    24 => Some(@public_input.F12)
    _ => None
  }
}

///|
fn modifiers_from_param(param : Int) -> @public_input.KeyModifiers {
  let bits = param - 1
  if bits <= 0 {
    @public_input.KeyModifiers::new()
  } else {
    @public_input.KeyModifiers::new(
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
) -> @public_input.InputEvent {
  match byte {
    b'\r' => @public_input.Key(@public_input.KeyEvent::new(@public_input.Enter))
    b'\n' =>
      @public_input.Key(
        @public_input.KeyEvent::new(
          @public_input.Char('j'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    b'\t' => @public_input.Key(@public_input.KeyEvent::new(@public_input.Tab))
    b'\x7f' | b'\x08' =>
      @public_input.Key(@public_input.KeyEvent::new(@public_input.Backspace))
    b'\x00' =>
      @public_input.Key(
        @public_input.KeyEvent::new(
          @public_input.Char(' '),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x01..=0x1a =>
      @public_input.Key(
        @public_input.KeyEvent::new(
          @public_input.Char(
            (byte.to_int() - 1 + 'a'.to_int()).unsafe_to_char(),
          ),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x1c..=0x1f =>
      @public_input.Key(
        @public_input.KeyEvent::new(
          @public_input.Char(
            (byte.to_int() - 0x1c + '4'.to_int()).unsafe_to_char(),
          ),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x20..<0x7f => {
      let char = byte.to_char()
      @public_input.Key(
        @public_input.KeyEvent::new(@public_input.Char(char), text=[char]),
      )
    }
    _ => read_utf8_text(reader, byte, esc_timeout_ms~)
  }
}

///|
async fn read_utf8_text(
  reader : EventReader,
  first : Byte,
  esc_timeout_ms~ : Int,
) -> @public_input.InputEvent {
  guard utf8_sequence_length(first) is Some(len) else {
    return @public_input.Unknown([first])
  }
  for _ in 1..<len {
    guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
      is Some(byte) else {
      return @public_input.Unknown(reader.view().to_owned())
    }
    if !is_utf8_continuation(byte) {
      reader.unread_byte()
      return @public_input.Unknown(reader.view().to_owned())
    }
  }
  let bytes = reader.view().to_owned()
  try @utf8.decode(bytes) catch {
    _ => @public_input.Unknown(bytes)
  } noraise {
    text => text_event(text)
  }
}

///|
fn text_event(text : String) -> @public_input.InputEvent {
  let mut count = 0
  let mut first = '\u{0}'
  for ch in text {
    if count == 0 {
      first = ch
    }
    count += 1
  }
  if count == 1 {
    @public_input.Key(
      @public_input.KeyEvent::new(@public_input.Char(first), text~),
    )
  } else {
    @public_input.Key(@public_input.KeyEvent::new(@public_input.Text, text~))
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
