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
  {
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
    Input(Key(@public_input.KeyEvent::new(Escape)))
  }
  match byte {
    Esc => {
      reader.unread_byte()
      Input(Key(@public_input.KeyEvent::new(Escape)))
    }
    b'[' => read_csi(reader, esc_timeout_ms~)
    b']' => read_osc(reader, esc_timeout_ms~)
    b'O' => Input(read_ss3(reader, esc_timeout_ms~))
    0x20..<0x7f as byte =>
      Input(
        Key(
          @public_input.KeyEvent::new(
            Char(byte.to_char()),
            modifiers=@public_input.KeyModifiers::new(alt=true),
          ),
        ),
      )
    _ => Input(Unknown(reader.view().to_owned()))
  }
}

///|
async fn read_osc(reader : EventReader, esc_timeout_ms~ : Int) -> Event {
  for ;; {
    guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
      is Some(byte) else {
      return match reader.view() {
        [Esc, b']'] =>
          Input(
            Key(
              @public_input.KeyEvent::new(
                Char(']'),
                modifiers=@public_input.KeyModifiers::new(alt=true),
              ),
            ),
          )
        _ => Input(Unknown(reader.view().to_owned()))
      }
    }
    match byte {
      b'\x07' => return parse_osc(reader.view())
      Esc => {
        guard @async.with_timeout_opt(esc_timeout_ms, () => reader.read_byte())
          is Some(byte) else {
          return Input(Unknown(reader.view().to_owned()))
        }
        if byte == b'\\' {
          return parse_osc(reader.view())
        }
      }
      _ => ()
    }
  }
}

///|
fn parse_osc(osc : BytesView) -> Event {
  match osc {
    [Esc, b']', .. body, b'\x07'] => parse_osc_body(osc, body)
    [Esc, b']', .. body, Esc, b'\\'] => parse_osc_body(osc, body)
    _ => Input(Unknown(osc.to_owned()))
  }
}

///|
fn parse_osc_body(osc : BytesView, body : BytesView) -> Event {
  match body {
    [.. b"10;rgb:", .. spec] => parse_dynamic_color(10, osc, spec)
    [.. b"11;rgb:", .. spec] => parse_dynamic_color(11, osc, spec)
    [.. b"12;rgb:", .. spec] => parse_dynamic_color(12, osc, spec)
    _ => Input(Unknown(osc.to_owned()))
  }
}

///|
fn parse_dynamic_color(code : Int, osc : BytesView, spec : BytesView) -> Event {
  guard parse_xparse_rgb(spec) is Some((red, green, blue)) else {
    return Input(Unknown(osc.to_owned()))
  }
  DynamicColor(code~, red~, green~, blue~)
}

///|
fn parse_xparse_rgb(spec : BytesView) -> (Int, Int, Int)? {
  guard parse_hex_color_component(spec, 0) is Some((red, offset)) else {
    return None
  }
  guard offset < spec.length() && spec[offset] == b'/' else { return None }
  guard parse_hex_color_component(spec, offset + 1) is Some((green, offset)) else {
    return None
  }
  guard offset < spec.length() && spec[offset] == b'/' else { return None }
  guard parse_hex_color_component(spec, offset + 1) is Some((blue, offset)) else {
    return None
  }
  guard offset == spec.length() else { return None }
  Some((red, green, blue))
}

///|
fn parse_hex_color_component(spec : BytesView, offset : Int) -> (Int, Int)? {
  let mut index = offset
  let mut value = 0
  let mut length = 0
  for ;; {
    guard index < spec.length() else { break }
    guard hex_digit(spec[index]) is Some(digit) else { break }
    guard length < 4 else { return None }
    value = value * 16 + digit
    length += 1
    index += 1
  }
  guard length > 0 else { return None }
  let scaled = match length {
    1 => value * 0x1111
    2 => value * 0x0101
    3 => value * 65535 / 4095
    4 => value
    _ => return None
  }
  Some((scaled, index))
}

///|
fn hex_digit(byte : Byte) -> Int? {
  match byte {
    b'0'..=b'9' => Some(byte.to_int() - b'0'.to_int())
    b'a'..=b'f' => Some(byte.to_int() - b'a'.to_int() + 10)
    b'A'..=b'F' => Some(byte.to_int() - b'A'.to_int() + 10)
    _ => None
  }
}

///|
async fn read_ss3(
  reader : EventReader,
  esc_timeout_ms~ : Int,
) -> @public_input.InputEvent {
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
            Key(
              @public_input.KeyEvent::new(
                Char('['),
                modifiers=@public_input.KeyModifiers::new(alt=true),
              ),
            ),
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
fn ss3_event(ss3 : BytesView) -> @public_input.InputEvent {
  match ss3 {
    [Esc, b'O', b'A'] => Key(@public_input.KeyEvent::new(Up))
    [Esc, b'O', b'B'] => Key(@public_input.KeyEvent::new(Down))
    [Esc, b'O', b'C'] => Key(@public_input.KeyEvent::new(Right))
    [Esc, b'O', b'D'] => Key(@public_input.KeyEvent::new(Left))
    [Esc, b'O', b'H'] => Key(@public_input.KeyEvent::new(Home))
    [Esc, b'O', b'F'] => Key(@public_input.KeyEvent::new(End))
    [Esc, b'O', b'P'] => Key(@public_input.KeyEvent::new(F1))
    [Esc, b'O', b'Q'] => Key(@public_input.KeyEvent::new(F2))
    [Esc, b'O', b'R'] => Key(@public_input.KeyEvent::new(F3))
    [Esc, b'O', b'S'] => Key(@public_input.KeyEvent::new(F4))
    _ => Unknown(ss3.to_owned())
  }
}

///|
fn parse_csi(csi : BytesView) -> Event {
  match csi {
    [Esc, b'[', b'?', .. params, b'u'] =>
      parse_keyboard_enhancement_flags(csi, params)
    [Esc, b'[', b'?', .. params, b'c'] =>
      parse_primary_device_attributes(csi, params)
    [Esc, b'[', .. params, b'u'] => Input(parse_kitty_key(csi, params))
    [Esc, b'[', b'Z'] =>
      Input(
        Key(
          @public_input.KeyEvent::new(
            Tab,
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      )
    [Esc, b'[', b'I'] => Input(FocusIn)
    [Esc, b'[', b'O'] => Input(FocusOut)
    [Esc, b'[', b'<', .. params, b'M'] =>
      Input(parse_sgr_mouse(csi, params, false))
    [Esc, b'[', b'<', .. params, b'm'] =>
      Input(parse_sgr_mouse(csi, params, true))
    [Esc, b'[', .. params, b'~'] => Input(parse_csi_tilde_key(csi, params))
    [Esc, b'[', .. params, final_byte] =>
      match final_byte {
        b'A' => Input(parse_csi_key(csi, params, Up))
        b'B' => Input(parse_csi_key(csi, params, Down))
        b'C' => Input(parse_csi_key(csi, params, Right))
        b'D' => Input(parse_csi_key(csi, params, Left))
        b'H' => Input(parse_csi_key(csi, params, Home))
        b'F' => Input(parse_csi_key(csi, params, End))
        b'P' => Input(parse_csi_key(csi, params, F1))
        b'Q' => Input(parse_csi_key(csi, params, F2))
        b'R' =>
          match @csi.parse_params(params) {
            Some(parsed) if parse_cursor_position_params(parsed)
              is Some((row, col)) => CursorPosition(row~, col~)
            _ => Input(parse_csi_key(csi, params, F3))
          }
        b'S' => Input(parse_csi_key(csi, params, F4))
        _ => Input(Unknown(csi.to_owned()))
      }
    _ => Input(Unknown(csi.to_owned()))
  }
}

///|
fn parse_keyboard_enhancement_flags(
  csi : BytesView,
  params : BytesView,
) -> Event {
  guard @csi.parse_decimal(params) is Some(flags) else {
    return Input(Unknown(csi.to_owned()))
  }
  KeyboardEnhancementFlags(flags)
}

///|
fn parse_primary_device_attributes(
  csi : BytesView,
  params : BytesView,
) -> Event {
  if @csi.is_primary_device_attributes_params(params) {
    PrimaryDeviceAttributes(csi.to_owned())
  } else {
    Input(Unknown(csi.to_owned()))
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
fn parse_sgr_mouse(
  csi : BytesView,
  params_bytes : BytesView,
  release : Bool,
) -> @public_input.InputEvent {
  guard @csi.parse_params(params_bytes) is Some(params) else {
    return Unknown(csi.to_owned())
  }
  let parsed = match params {
    [Some(cb), Some(col), Some(row)] => Some((cb, col, row))
    [Some(cb), Some(col), Some(row), None] => Some((cb, col, row))
    _ => None
  }
  guard parsed is Some((cb, col, row)) else { return Unknown(csi.to_owned()) }
  guard cb >= 0 && row >= 1 && col >= 1 else { return Unknown(csi.to_owned()) }
  guard mouse_event_kind_from_cb(cb, release~) is Some(kind) else {
    return Unknown(csi.to_owned())
  }
  Mouse(
    @public_input.MouseEvent::new(
      kind,
      row,
      col,
      modifiers=mouse_modifiers_from_cb(cb),
    ),
  )
}

///|
fn mouse_event_kind_from_cb(
  cb : Int,
  release~ : Bool,
) -> @public_input.MouseEventKind? {
  if cb < 0 || cb > 127 {
    return None
  }
  let button = cb & 3
  let dragging = (cb & 32) != 0
  let wheel = (cb & 64) != 0
  if release {
    if wheel || dragging {
      return None
    }
    match button {
      0 => Some(Release(Left))
      1 => Some(Release(Middle))
      2 => Some(Release(Right))
      _ => None
    }
  } else if wheel {
    match button {
      0 => Some(Scroll(Up))
      1 => Some(Scroll(Down))
      2 => Some(Scroll(Left))
      3 => Some(Scroll(Right))
      _ => None
    }
  } else if dragging {
    match button {
      0 => Some(Drag(Left))
      1 => Some(Drag(Middle))
      2 => Some(Drag(Right))
      3 => Some(Move)
      _ => None
    }
  } else {
    match button {
      0 => Some(Press(Left))
      1 => Some(Press(Middle))
      2 => Some(Press(Right))
      _ => None
    }
  }
}

///|
fn mouse_modifiers_from_cb(cb : Int) -> @public_input.KeyModifiers {
  @public_input.KeyModifiers::new(
    shift=(cb & 4) != 0,
    alt=(cb & 8) != 0,
    ctrl=(cb & 16) != 0,
  )
}

///|
fn parse_csi_key(
  csi : BytesView,
  params_bytes : BytesView,
  code : @public_input.KeyCode,
) -> @public_input.InputEvent {
  guard @csi.parse_subparams(params_bytes) is Some(params) else {
    return Unknown(csi.to_owned())
  }
  guard parse_csi_key_event(params, code) is Some(key) else {
    return Unknown(csi.to_owned())
  }
  Key(key)
}

///|
fn parse_csi_key_event(
  params : Array[Array[Int?]],
  code : @public_input.KeyCode,
) -> @public_input.KeyEvent? {
  match params {
    [] | [[None | Some(1)]] | [[None | Some(1)], [None]] =>
      Some(@public_input.KeyEvent::new(code))
    [[None | Some(1)], [Some(modifier)]] =>
      Some(
        @public_input.KeyEvent::new(
          code,
          modifiers=legacy_modifiers_from_param(modifier),
        ),
      )
    [[None | Some(1)], modifier_event] =>
      match @kitty.parse_modifier_report(modifier_event) {
        Some(report) => Some(report.key_event(code))
        None => None
      }
    _ => None
  }
}

///|
fn parse_csi_tilde_key(
  csi : BytesView,
  params_bytes : BytesView,
) -> @public_input.InputEvent {
  guard @csi.parse_subparams(params_bytes) is Some(params) else {
    return Unknown(csi.to_owned())
  }
  let key = match params {
    [[Some(code)]] =>
      match tilde_key_code(code) {
        Some(key_code) => @public_input.KeyEvent::new(key_code)
        None => return Unknown(csi.to_owned())
      }
    [[Some(code)], [None]] =>
      match tilde_key_code(code) {
        Some(key_code) => @public_input.KeyEvent::new(key_code)
        None => return Unknown(csi.to_owned())
      }
    [[Some(code)], [Some(modifier)]] =>
      match tilde_key_code(code) {
        Some(key_code) =>
          @public_input.KeyEvent::new(
            key_code,
            modifiers=legacy_modifiers_from_param(modifier),
          )
        None => return Unknown(csi.to_owned())
      }
    [[Some(code)], modifier_event] =>
      match @kitty.parse_modifier_report(modifier_event) {
        Some(report) =>
          match tilde_key_code(code) {
            Some(key_code) => report.key_event(key_code)
            None => return Unknown(csi.to_owned())
          }
        None => return Unknown(csi.to_owned())
      }
    _ => return Unknown(csi.to_owned())
  }
  Key(key)
}

///|
fn tilde_key_code(code : Int) -> @public_input.KeyCode? {
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
fn legacy_modifiers_from_param(param : Int) -> @public_input.KeyModifiers {
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
fn parse_kitty_key(
  csi : BytesView,
  params_bytes : BytesView,
) -> @public_input.InputEvent {
  guard @csi.parse_subparams(params_bytes) is Some(params) else {
    return Unknown(csi.to_owned())
  }
  match @kitty.parse_key(params) {
    Some(key) => Key(key)
    None => Unknown(csi.to_owned())
  }
}

///|
async fn read_byte_event(
  reader : EventReader,
  byte : Byte,
  esc_timeout_ms : Int,
) -> @public_input.InputEvent {
  match byte {
    b'\r' => Key(@public_input.KeyEvent::new(Enter))
    b'\n' =>
      Key(
        @public_input.KeyEvent::new(
          Char('j'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    b'\t' => Key(@public_input.KeyEvent::new(Tab))
    b'\x7f' | b'\x08' => Key(@public_input.KeyEvent::new(Backspace))
    b'\x00' =>
      Key(
        @public_input.KeyEvent::new(
          Char(' '),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x01..=0x1a =>
      Key(
        @public_input.KeyEvent::new(
          Char((byte.to_int() - 1 + 'a'.to_int()).unsafe_to_char()),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x1c..=0x1f =>
      Key(
        @public_input.KeyEvent::new(
          Char((byte.to_int() - 0x1c + '4'.to_int()).unsafe_to_char()),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    0x20..<0x7f => {
      let char = byte.to_char()
      Key(@public_input.KeyEvent::new(Char(char), text=[char]))
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
    Key(@public_input.KeyEvent::new(Char(first), text~))
  } else {
    Key(@public_input.KeyEvent::new(Text, text~))
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
