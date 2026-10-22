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
const TAG_HELLO : UInt32 = 0x80

///|
const TAG_INPUT : UInt32 = 0x81

///|
const TAG_RESIZE : UInt32 = 0x82

///|
const TAG_ERROR : UInt32 = 0x83

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
/// Next frame from the sidecar, `None` once it has closed its output.
pub async fn Connection::read_frame(self : Connection) -> Frame? {
  let header = FixedArray::make(5, b'\x00')
  guard self.read_full(header) else { return None }
  guard header is [u8be(tag), u32le(len)] else {
    raise ProtocolError("malformed sidecar frame header")
  }
  if len > MAX_PAYLOAD.reinterpret_as_uint() {
    raise ProtocolError("sidecar frame length \{len} out of range")
  }
  let len = len.reinterpret_as_int()
  let payload = FixedArray::make(len, b'\x00')
  if len > 0 && !self.read_full(payload) {
    raise ProtocolError("sidecar closed in the middle of a frame")
  }
  let payload = Bytes::from_array(payload[:])
  match (tag, payload[:]) {
    (TAG_HELLO, [u32le(version), u16le(rows), u16le(cols), ..]) =>
      Some(
        Hello(
          version=version.reinterpret_as_int(),
          rows=rows.reinterpret_as_int(),
          cols=cols.reinterpret_as_int(),
        ),
      )
    (TAG_HELLO, _) => raise ProtocolError("short hello frame")
    (TAG_INPUT, _) => Some(Input(payload))
    (TAG_RESIZE, [u16le(rows), u16le(cols), ..]) =>
      Some(
        Resize(rows=rows.reinterpret_as_int(), cols=cols.reinterpret_as_int()),
      )
    (TAG_RESIZE, _) => raise ProtocolError("short resize frame")
    (TAG_ERROR, _) => Some(Error(@utf8.decode_lossy(payload)))
    (tag, _) => raise ProtocolError("unknown sidecar frame tag \{tag}")
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
