///|
/// Frame protocol spoken with `sidecar/sidecar.c`, see `sidecar/README.md`.
/// Every frame is `tag:u8 len:u32le payload`.
pub(all) enum Frame {
  Hello(version~ : Int32, rows~ : Int32, cols~ : Int32, kind~ : InputKind)
  /// Terminal input as VT bytes (Unix sidecar).
  Input(Bytes)
  /// One raw `INPUT_RECORD` (Windows sidecar), decoded by `internal/win32`.
  Record(Bytes)
  Resize(rows~ : Int32, cols~ : Int32)
  Error(String)
} derive(Eq, Debug)

///|
/// What the sidecar's input frames carry, announced in `Hello`.
pub(all) enum InputKind {
  Bytes
  Records
} derive(Eq, Debug)

///|
pub extend InputKind with Eq::{equal, not_equal}

///|
pub extend InputKind with @debug.Debug::{to_repr}

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
const TAG_RECORD : UInt32 = 0x84

///|
/// Largest payload we accept from the sidecar; it never sends more than its
/// own 4 KB read buffer, so anything beyond this is corruption.
const MAX_PAYLOAD : Int32 = 1 << 20

///|
/// Largest payload we send in one frame. The sidecar parses commands out of
/// a 64 KiB buffer, so a frame must stay well below that; `write` splits.
pub const MAX_WRITE : Int32 = 32 * 1024

///|
const HEADER_SIZE : Int32 = 5

///|
/// Size of one raw Windows `INPUT_RECORD`, the payload of every RECORD frame.
const RECORD_SIZE : Int32 = 20

///|
/// Frame encoder and decoder over a byte stream pair.
///
/// Incoming bytes are accumulated in `buf` and frames are cut from there,
/// so a read that is cancelled (a query timeout, the decoder's escape
/// disambiguation) can only ever lose a read that had not returned yet; a
/// header or partial payload already received stays in the buffer.
struct Connection {
  reader : &@async/io.Reader
  writer : &@async/io.Writer
  mut buf : FixedArray[Byte]
  mut len : Int32
  // A frame is one transaction on the command pipe: concurrent senders are
  // serialized and a frame once started is not cut short by cancellation.
  send_lock : @lock.Lock
  // Set once a send failed part way: the sidecar is then waiting for the
  // rest of that frame and nothing sent later can be parsed correctly.
  mut broken : Bool
}

///|
pub fn Connection::new(
  reader : &@async/io.Reader,
  writer : &@async/io.Writer,
) -> Connection {
  {
    reader,
    writer,
    buf: FixedArray::make(4096, b'\x00'),
    len: 0,
    send_lock: @lock.Lock::new(),
    broken: false,
  }
}

///|
/// Make sure at least `needed` bytes are buffered. Returns `false` on a
/// clean EOF before the first byte of a frame, raises on EOF inside one.
async fn Connection::fill(self : Connection, needed : Int32) -> Bool {
  if self.buf.length() < needed {
    let grown = FixedArray::make(needed, b'\x00')
    for i in 0..<self.len {
      grown[i] = self.buf[i]
    }
    self.buf = grown
  }
  while self.len < needed {
    let n = self.reader.read(
      self.buf,
      offset=self.len,
      max_len=self.buf.length() - self.len,
    )
    if n == 0 {
      if self.len == 0 {
        return false
      }
      raise ProtocolError("sidecar closed in the middle of a frame")
    }
    self.len += n
  }
  true
}

///|
/// Drop the first `count` buffered bytes.
fn Connection::consume(self : Connection, count : Int32) -> Unit {
  for i in count..<self.len {
    self.buf[i - count] = self.buf[i]
  }
  self.len -= count
}

///|
/// Next frame from the sidecar, `None` once it has closed its output.
pub async fn Connection::read_frame(self : Connection) -> Frame? {
  guard self.fill(HEADER_SIZE) else { return None }
  guard self.buf[:HEADER_SIZE] is [u8be(tag), u32le(len)] else {
    raise ProtocolError("malformed sidecar frame header")
  }
  if len > MAX_PAYLOAD.reinterpret_as_uint() {
    raise ProtocolError("sidecar frame length \{len} out of range")
  }
  let len = len.reinterpret_as_int()
  guard self.fill(HEADER_SIZE + len) else {
    raise ProtocolError("sidecar closed in the middle of a frame")
  }
  let payload = Bytes::from_array(self.buf[HEADER_SIZE:HEADER_SIZE + len])
  self.consume(HEADER_SIZE + len)
  match (tag, payload[:]) {
    (TAG_HELLO, [u32le(version), u16le(rows), u16le(cols), u8be(kind)]) =>
      Some(
        Hello(
          version=version.reinterpret_as_int(),
          rows=rows.reinterpret_as_int(),
          cols=cols.reinterpret_as_int(),
          kind=match kind {
            0 => Bytes
            1 => Records
            kind => raise ProtocolError("unknown sidecar input kind \{kind}")
          },
        ),
      )
    (TAG_HELLO, _) => raise ProtocolError("malformed hello frame")
    (TAG_INPUT, _) => Some(Input(payload))
    (TAG_RECORD, _) if len == RECORD_SIZE => Some(Record(payload))
    (TAG_RECORD, _) => raise ProtocolError("record frame of \{len} bytes")
    (TAG_RESIZE, [u16le(rows), u16le(cols)]) =>
      Some(
        Resize(rows=rows.reinterpret_as_int(), cols=cols.reinterpret_as_int()),
      )
    (TAG_RESIZE, _) => raise ProtocolError("malformed resize frame")
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
  let frame = buf.contents()
  self.send_lock.with_lock(() => {
    guard !self.broken else {
      raise ProtocolError("sidecar connection broken by an earlier failed send")
    }
    @async.protect_from_cancel(() => {
      errdefer self.mark_broken()
      self.writer.write(frame)
    })
  })
}

///|
fn Connection::mark_broken(self : Connection) -> Unit {
  self.broken = true
}

///|
pub async fn Connection::set_raw(self : Connection, on : Bool) -> Unit {
  self.send(TAG_SET_RAW, if on { b"\x01" } else { b"\x00" })
}

///|
/// Write `data` to the terminal, in frames of at most `MAX_WRITE` bytes.
pub async fn Connection::write(self : Connection, data : BytesView) -> Unit {
  let mut rest = data
  while rest.length() > MAX_WRITE {
    self.send(TAG_WRITE, rest[:MAX_WRITE])
    rest = rest[MAX_WRITE:]
  }
  self.send(TAG_WRITE, rest)
}
