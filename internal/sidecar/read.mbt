///|
/// Raised when the sidecar sends bytes that do not fit the protocol.
pub(all) suberror ProtocolViolation derive(Debug, ToJson)

///|
/// Payload length of a decoded frame, capped by the protocol maximum.
fn FrameHeader::payload_len(self : FrameHeader) -> Int raise {
  match self {
    Ok(payload_len~, ..) | Err(payload_len~, ..) | Event(payload_len~) =>
      if payload_len > MAX_PAYLOAD {
        raise ProtocolViolation
      } else {
        payload_len
      }
  }
}

///|
/// Read and decode the reply to `request` from the control connection.
/// Sidecar-reported failures come back as `Response::Error`, not as a raised
/// error; raising is reserved for broken streams (`ProtocolViolation`,
/// `ReaderClosed`).
///
/// Control round-trips must not be cancelled mid-read (a torn read desyncs
/// the connection for every later request); callers serialize and protect
/// them.
pub async fn Response::read(
  reader : &@async/io.Reader,
  request : Request,
  id~ : UInt,
) -> Response {
  let header = reader.read_exactly(HEADER_SIZE)
  guard FrameHeader::decode(header) is Some(frame_header) else {
    raise ProtocolViolation
  }
  let payload = reader.read_exactly(frame_header.payload_len())
  guard Response::decode(request, id~, header, payload) is Some(response) else {
    raise ProtocolViolation
  }
  response
}

///|
/// Read a connection handshake and validate it against the expected magic
/// and token, raising `ProtocolViolation` on any mismatch.
pub async fn read_handshake(
  reader : &@async/io.Reader,
  magic~ : UInt,
  token~ : Bytes,
) -> Unit {
  guard reader.read_exactly(HANDSHAKE_SIZE)
    is [u32le(peer_magic), u16le(proto), u16le(token_len)] else {
    raise ProtocolViolation
  }
  guard peer_magic == magic &&
    proto.reinterpret_as_int() == PROTO_VERSION &&
    token_len.reinterpret_as_int() == token.length() &&
    token.length() <= MAX_TOKEN else {
    raise ProtocolViolation
  }
  if reader.read_exactly(token.length()) != token {
    raise ProtocolViolation
  }
}

///|
/// Cancellation-safe reader for the event connection.
///
/// Event waiters race against other input sources and get cancelled
/// routinely, so frames must never be torn: every byte pulled from the
/// reader lands in a window that survives cancellation, and the single
/// `read` per iteration either completes or consumes nothing.
struct EventStream {
  reader : &@async/io.Reader
  mut data : FixedArray[Byte]
  mut len : Int
}

///|
pub fn EventStream::EventStream(reader : &@async/io.Reader) -> EventStream {
  { reader, data: FixedArray::make(64, b'\x00'), len: 0 }
}

///|
/// Read the next terminal event, skipping unknown event codes so future
/// sidecars can add events without breaking older parents.
pub async fn EventStream::next(self : EventStream) -> Event {
  for ;; {
    match self.buffered_event() {
      Some(event) => return event
      None => ()
    }
    self.ensure_capacity()
    let n = self.reader.read(
      self.data,
      offset=self.len,
      max_len=self.data.length() - self.len,
    )
    if n == 0 {
      raise @async/io.ReaderClosed
    }
    self.len += n
  }
}

///|
/// Decode and consume the next complete event frame in the window, if any.
/// Unknown event codes are consumed and skipped.
fn EventStream::buffered_event(self : EventStream) -> Event? raise {
  for ;; {
    if self.len < HEADER_SIZE {
      return None
    }
    let window = self.data.unsafe_reinterpret_as_bytes()
    guard FrameHeader::decode(window[0:HEADER_SIZE]) is Some(header) else {
      raise ProtocolViolation
    }
    guard header is Event(..) else { raise ProtocolViolation }
    let payload_len = header.payload_len()
    if self.len < HEADER_SIZE + payload_len {
      return None
    }
    let event = match window[HEADER_SIZE:HEADER_SIZE + payload_len] {
      [1, i32le(rows), i32le(cols), ..] => Some(Resize(rows~, cols~))
      [2, .. records] => {
        guard records.length() % INPUT_RECORD_SIZE == 0 else {
          raise ProtocolViolation
        }
        Some(InputRecords(records=records.to_owned()))
      }
      [] => raise ProtocolViolation
      _ => None // unknown event code: skip for forward compatibility
    }
    self.consume(HEADER_SIZE + payload_len)
    match event {
      Some(event) => return Some(event)
      None => continue
    }
  }
}

///|
fn EventStream::consume(self : EventStream, frame_len : Int) -> Unit {
  let remaining = self.len - frame_len
  if remaining > 0 {
    self.data.blit_to(self.data, len=remaining, src_offset=frame_len)
  }
  self.len = remaining
}

///|
/// Make room to buffer at least one more byte, sized so any legal frame
/// eventually fits.
fn EventStream::ensure_capacity(self : EventStream) -> Unit {
  if self.len < self.data.length() {
    return
  }
  let data = FixedArray::make(self.data.length() * 2, b'\x00')
  self.data.blit_to(data, len=self.len)
  self.data = data
}
