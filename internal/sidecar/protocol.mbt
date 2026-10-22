///|
/// Frame protocol spoken with `sidecar/sidecar.c`, see `sidecar/README.md`.
/// Every frame is `tag:u8 len:u32le payload`.
pub(all) enum Frame {
  Hello(version~ : Int32, rows~ : Int32, cols~ : Int32)
  Input(Bytes)
  Resize(rows~ : Int32, cols~ : Int32)
  Error(String)
} derive(Eq, Debug)

///|
pub extend Frame with Eq::{equal, not_equal}

///|
pub extend Frame with @debug.Debug::{to_repr}

///|
/// The sidecar sent something we cannot make sense of.
pub suberror ProtocolError {
  ProtocolError(String)
} derive(Debug)

///|
pub extend ProtocolError with @debug.Debug::{to_repr}

///|
const TAG_SET_RAW : Byte = 0x01

///|
const TAG_WRITE : Byte = 0x02

///|
const TAG_HELLO : Byte = 0x80

///|
const TAG_INPUT : Byte = 0x81

///|
const TAG_RESIZE : Byte = 0x82

///|
const TAG_ERROR : Byte = 0x83

///|
/// Largest payload we accept from the sidecar; it never sends more than its
/// own 4 KB read buffer, so anything beyond this is corruption.
const MAX_PAYLOAD : Int32 = 1 << 20

///|
/// Frame encoder and decoder over a byte stream pair.
struct Connection {
  reader : &@async/io.Reader
  writer : &@async/io.Writer
}

///|
pub fn Connection::new(
  reader : &@async/io.Reader,
  writer : &@async/io.Writer,
) -> Connection {
  { reader, writer, }
}

///|
/// Fill `buf` completely. Returns `false` on a clean EOF before the first
/// byte, raises on EOF in the middle of a frame.
async fn Connection::read_full(
  self : Connection,
  buf : FixedArray[Byte],
) -> Bool {
  let mut filled = 0
  while filled < buf.length() {
    let n = self.reader.read(buf, offset=filled, max_len=buf.length() - filled)
    if n == 0 {
      if filled == 0 {
        return false
      }
      raise ProtocolError("sidecar closed in the middle of a frame")
    }
    filled += n
  }
  true
}

///|
fn u16_le(bytes : BytesView) -> Int32 {
  bytes[0].to_int() | (bytes[1].to_int() << 8)
}

///|
/// Next frame from the sidecar, `None` once it has closed its output.
pub async fn Connection::read_frame(self : Connection) -> Frame? {
  let header = FixedArray::make(5, b'\x00')
  guard self.read_full(header) else { return None }
  let len = header[1].to_int() |
    (header[2].to_int() << 8) |
    (header[3].to_int() << 16) |
    (header[4].to_int() << 24)
  if len < 0 || len > MAX_PAYLOAD {
    raise ProtocolError("sidecar frame length \{len} out of range")
  }
  let payload = FixedArray::make(len, b'\x00')
  if len > 0 && !self.read_full(payload) {
    raise ProtocolError("sidecar closed in the middle of a frame")
  }
  let payload = Bytes::from_array(payload[:])
  match header[0] {
    TAG_HELLO => {
      guard len >= 8 else { raise ProtocolError("short hello frame") }
      let version = payload[0].to_int() |
        (payload[1].to_int() << 8) |
        (payload[2].to_int() << 16) |
        (payload[3].to_int() << 24)
      Some(
        Hello(version~, rows=u16_le(payload[4:6]), cols=u16_le(payload[6:8])),
      )
    }
    TAG_INPUT => Some(Input(payload))
    TAG_RESIZE => {
      guard len >= 4 else { raise ProtocolError("short resize frame") }
      Some(Resize(rows=u16_le(payload[0:2]), cols=u16_le(payload[2:4])))
    }
    TAG_ERROR => Some(Error(@utf8.decode_lossy(payload)))
    tag => raise ProtocolError("unknown sidecar frame tag \{tag}")
  }
}

///|
async fn Connection::send(
  self : Connection,
  tag : Byte,
  payload : BytesView,
) -> Unit {
  let buf = @buffer.Buffer(size_hint=5 + payload.length())
  buf.write_byte(tag)
  buf.write_uint_le(payload.length().reinterpret_as_uint())
  buf.write_bytes(payload)
  self.writer.write(buf.contents())
}

///|
pub async fn Connection::set_raw(self : Connection, on : Bool) -> Unit {
  self.send(TAG_SET_RAW, if on { b"\x01" } else { b"\x00" })
}

///|
pub async fn Connection::write(self : Connection, data : BytesView) -> Unit {
  self.send(TAG_WRITE, data)
}
