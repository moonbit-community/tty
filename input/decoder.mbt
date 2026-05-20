///|
/// Stateful terminal input decoder.
///
/// `Decoder` owns the incomplete byte sequence between reads. Feed bytes from a
/// terminal input source with `parse_to`, drain complete events, and call
/// `flush_to` when no more bytes are immediately available so ambiguous prefixes
/// such as a single ESC can be resolved.
struct Decoder {
  mut data : FixedArray[Byte]
  mut head : Int
  mut tail : Int
  events : Array[Event]
}

///|
const DecoderBufferSize = 4096

///|
pub fn Decoder::new() -> Decoder {
  Decoder::{
    data: FixedArray::make(DecoderBufferSize, 0),
    head: 0,
    tail: 0,
    events: Array::new(),
  }
}

///|
pub fn Decoder::length(self : Decoder) -> Int {
  self.tail - self.head
}

///|
pub fn Decoder::capacity(self : Decoder) -> Int {
  self.data.length()
}

///|
fn Decoder::grow_by(self : Self, extra : Int) -> Unit {
  let length = self.length()
  let needed = length + extra
  let capacity = self.capacity()
  if self.tail + extra <= capacity {
    return
  }
  if needed <= capacity {
    self.data.blit_to(self.data, src_offset=self.head, len=length)
    self.head = 0
    self.tail = length
    return
  }
  let mut target = capacity
  while target < needed {
    target = target * 2
  }
  let new_buffer = FixedArray::make(target, b'\x00')
  self.data.blit_to(new_buffer, src_offset=self.head, len=length)
  self.data = new_buffer
  self.head = 0
  self.tail = length
}

///|
fn Decoder::skip(self : Self, n : Int) -> Unit {
  guard n <= self.length()
  self.head += n
  if self.head == self.tail {
    self.head = 0
    self.tail = 0
  }
}

///|
fn Decoder::skip_to(self : Self, rest : BytesView) -> Unit {
  let next = rest.start_offset()
  guard next >= self.head && next <= self.tail
  guard next + rest.length() == self.tail
  self.head = next
  if self.head == self.tail {
    self.head = 0
    self.tail = 0
  }
}

///|
fn Decoder::clear_pending(self : Self) -> Unit {
  self.head = 0
  self.tail = 0
}

///|
fn Decoder::view(self : Self) -> BytesView {
  self.data.unsafe_reinterpret_as_bytes()[self.head:self.tail]
}

///|
fn Decoder::unknown_to(
  self : Self,
  rest : BytesView,
  events : Array[Event],
) -> Unit {
  let len = self.length() - rest.length()
  events.push(Unknown(self.view().view(end=len).to_owned()))
  self.skip_to(rest)
}

///|
pub fn Decoder::push(self : Self, bytes : BytesView) -> Unit {
  let length = bytes.length()
  if length == 0 {
    return
  }
  self.grow_by(length)
  self.data.blit_from_bytesview(self.tail, bytes)
  self.tail += length
}

///|
pub fn Decoder::parse_to(
  self : Self,
  bytes : BytesView,
  events : Array[Event],
) -> Unit {
  self.push(bytes)
  self.drain_to(events)
}

///|
fn Decoder::drain_to(self : Self, events : Array[Event]) -> Unit {
  while self.length() > 0 {
    let view = self.view()
    match view {
      [b'\x1b'] => return
      [b'\x1b', b'[', .. rest] =>
        if self.parse_csi(rest, events) {
          continue
        } else {
          return
        }
      [b'\x1b', b'\x1b', ..] => {
        events.push(key(Escape))
        self.skip(1)
        continue
      }
      [b'\x1b', byte, .. rest] => {
        match alt_key(byte) {
          Some(event) => {
            events.push(event)
            self.skip_to(rest)
          }
          None => self.unknown_to(rest, events)
        }
        continue
      }
      [b'\r', .. rest] => {
        events.push(key(Enter))
        self.skip_to(rest)
        continue
      }
      [b'\n', .. rest] => {
        events.push(modified_key(Char('j'), KeyModifiers::new(ctrl=true)))
        self.skip_to(rest)
        continue
      }
      [b'\t', .. rest] => {
        events.push(key(Tab))
        self.skip_to(rest)
        continue
      }
      [b'\x7f' | b'\x08', .. rest] => {
        events.push(key(Backspace))
        self.skip_to(rest)
        continue
      }
      [b'\x00', .. rest] => {
        events.push(modified_key(Char(' '), KeyModifiers::new(ctrl=true)))
        self.skip_to(rest)
        continue
      }
      [byte, .. rest] => {
        events.push(byte_event(byte))
        self.skip_to(rest)
        continue
      }
      [] => return
    }
  }
}

///|
pub fn Decoder::flush_to(self : Self, events : Array[Event]) -> Unit {
  self.drain_to(events)
  if self.length() == 0 {
    return
  }
  match self.view() {
    [b'\x1b'] => {
      events.push(key(Escape))
      self.clear_pending()
    }
    _ => {
      events.push(Unknown(self.view().to_owned()))
      self.clear_pending()
    }
  }
}

///|
pub fn Decoder::has_pending(self : Self) -> Bool {
  self.events.length() > 0 || self.length() > 0
}

///|
pub fn Decoder::next(self : Self) -> Event? {
  if self.events.length() > 0 {
    return Some(self.events.remove(0))
  }
  self.drain_to(self.events)
  if self.events.length() > 0 {
    Some(self.events.remove(0))
  } else {
    None
  }
}

///|
pub fn Decoder::flush(self : Self) -> Event? {
  match self.next() {
    Some(event) => Some(event)
    None => {
      self.flush_to(self.events)
      if self.events.length() > 0 {
        Some(self.events.remove(0))
      } else {
        None
      }
    }
  }
}

///|
pub fn Decoder::clear(self : Self) -> Unit {
  self.clear_pending()
  self.events.clear()
}

///|
fn Decoder::parse_csi(
  self : Self,
  rest : BytesView,
  events : Array[Event],
) -> Bool {
  let mut seen_intermediate = false
  let mut i = 0
  while i < rest.length() {
    let byte = rest[i]
    if byte >= 0x30 && byte < 0x40 {
      if seen_intermediate {
        self.unknown_to(rest.view(start=i + 1), events)
        return true
      }
    } else if byte >= 0x20 && byte < 0x30 {
      seen_intermediate = true
    } else if is_csi_final(byte) {
      self.emit_csi(rest.view(end=i + 1), rest.view(start=i + 1), events)
      return true
    } else {
      self.unknown_to(rest.view(start=i + 1), events)
      return true
    }
    i += 1
  }
  false
}

///|
fn Decoder::emit_csi(
  self : Self,
  csi : BytesView,
  rest : BytesView,
  events : Array[Event],
) -> Unit {
  match csi {
    [b'A'] => self.emit_to(rest, key(Up), events)
    [b'B'] => self.emit_to(rest, key(Down), events)
    [b'C'] => self.emit_to(rest, key(Right), events)
    [b'D'] => self.emit_to(rest, key(Left), events)
    [b'H'] => self.emit_to(rest, key(Home), events)
    [b'F'] => self.emit_to(rest, key(End), events)
    [b'Z'] =>
      self.emit_to(
        rest,
        modified_key(Tab, KeyModifiers::new(shift=true)),
        events,
      )
    [b'2', b'~'] => self.emit_to(rest, key(Insert), events)
    [b'3', b'~'] => self.emit_to(rest, key(Delete), events)
    [b'5', b'~'] => self.emit_to(rest, key(PageUp), events)
    [b'6', b'~'] => self.emit_to(rest, key(PageDown), events)
    _ => self.unknown_to(rest, events)
  }
}

///|
fn Decoder::emit_to(
  self : Self,
  rest : BytesView,
  event : Event,
  events : Array[Event],
) -> Unit {
  events.push(event)
  self.skip_to(rest)
}

///|
fn is_csi_final(byte : Byte) -> Bool {
  byte is (0x40..<0x7f)
}

///|
fn key(code : KeyCode) -> Event {
  Key(KeyEvent::{ code, modifiers: KeyModifiers::new(), text: None })
}

///|
fn modified_key(code : KeyCode, modifiers : KeyModifiers) -> Event {
  Key(KeyEvent::{ code, modifiers, text: None })
}

///|
fn text_key(byte : Byte) -> Event {
  Key(KeyEvent::{
    code: Char(byte.to_char()),
    modifiers: KeyModifiers::new(),
    text: Some(Bytes::from_array([byte]).to_unchecked_string()),
  })
}

///|
fn byte_event(byte : Byte) -> Event {
  match byte {
    0x01..=0x1a =>
      modified_key(
        Char((byte.to_int() - 1 + 'a'.to_int()).unsafe_to_char()),
        KeyModifiers::new(ctrl=true),
      )
    0x1c..=0x1f =>
      modified_key(
        Char((byte.to_int() - 0x1c + '4'.to_int()).unsafe_to_char()),
        KeyModifiers::new(ctrl=true),
      )
    0x20..<0x7f => text_key(byte)
    _ => Unknown(Bytes::from_array([byte]))
  }
}

///|
fn alt_key(byte : Byte) -> Event? {
  match byte {
    0x20..<0x7f =>
      Some(
        Key(KeyEvent::{
          code: Char(byte.to_char()),
          modifiers: KeyModifiers::new(alt=true),
          text: None,
        }),
      )
    _ => None
  }
}
