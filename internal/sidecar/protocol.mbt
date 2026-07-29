///|
/// Wire protocol shared with `sidecar/tty_sidecar.c` (see
/// `sidecar/PROTOCOL.md`). All integers are little-endian. Only the encoded
/// requests and fully decoded replies/events are public; framing stays
/// internal to this package.
const PROTO_VERSION : Int = 1

///|
/// `"MTTC"` — handshake magic of the control connection.
pub const MAGIC_CONTROL : UInt = 0x4354544D

///|
/// `"MTTE"` — handshake magic of the event connection.
pub const MAGIC_EVENT : UInt = 0x4554544D

///|
/// Byte size of one Win32 `INPUT_RECORD` in an `InputRecords` event payload.
pub const INPUT_RECORD_SIZE : Int = 20

///|
/// Byte size of request and response frame headers.
const HEADER_SIZE : Int = 7

///|
/// Byte size of the handshake prefix before the token bytes.
const HANDSHAKE_SIZE : Int = 8

///|
/// Upper bound on frame payloads, mirrored from the sidecar's `MAX_PAYLOAD`.
const MAX_PAYLOAD : Int = 4096

///|
/// Upper bound on handshake tokens, mirrored from the sidecar's `MAX_TOKEN`.
const MAX_TOKEN : Int = 256

///|
const OP_ISATTY : Byte = 0x01

///|
const OP_ENTER_RAW : Byte = 0x02

///|
const OP_LEAVE_RAW : Byte = 0x03

///|
const OP_WINSIZE : Byte = 0x05

///|
const OP_WATCH : Byte = 0x06

///|
const OP_SHUTDOWN : Byte = 0x07

///|
/// A request from the parent to the sidecar. Slots (`which`/`input`/`output`)
/// name the sidecar's inherited stdio descriptors: 0 stdin, 1 stdout,
/// 2 stderr.
///
/// `Watch` gates terminal-event delivery: resize notifications on Unix, and
/// exclusive console `INPUT_RECORD` streaming on Windows.
pub(all) enum Request {
  IsATty(which~ : Int)
  EnterRawMode(input~ : Int, output~ : Int)
  LeaveRawMode(input~ : Int, output~ : Int)
  WinSize(which~ : Int)
  Watch(enable~ : Bool)
  Shutdown
} derive(Eq, Debug)

///|
fn frame(op : Byte, id : UInt, payload : Bytes) -> Bytes {
  let buf = Buffer(size_hint=HEADER_SIZE + payload.length())
  buf.write_byte(op)
  buf.write_uint_le(id)
  buf.write_uint16_le(payload.length().to_uint16())
  buf.write_bytes(payload)
  buf.contents()
}

///|
pub fn Request::encode(self : Request, id~ : UInt) -> Bytes {
  match self {
    IsATty(which~) => frame(OP_ISATTY, id, Bytes::make(1, which.to_byte()))
    EnterRawMode(input~, output~) =>
      frame(OP_ENTER_RAW, id, [input.to_byte(), output.to_byte()])
    LeaveRawMode(input~, output~) =>
      frame(OP_LEAVE_RAW, id, [input.to_byte(), output.to_byte()])
    WinSize(which~) => frame(OP_WINSIZE, id, Bytes::make(1, which.to_byte()))
    Watch(enable~) =>
      frame(OP_WATCH, id, Bytes::make(1, enable.to_int().to_byte()))
    Shutdown => frame(OP_SHUTDOWN, id, b"")
  }
}

///|
/// Framing detail of sidecar-to-parent frames; only decoded forms are public.
priv enum FrameHeader {
  Ok(id~ : UInt, payload_len~ : Int)
  Err(id~ : UInt, payload_len~ : Int)
  Event(payload_len~ : Int)
}

///|
fn FrameHeader::decode(header : BytesView) -> FrameHeader? {
  match header {
    [0, u32le(id), u16le(len)] =>
      Some(Ok(id~, payload_len=len.reinterpret_as_int()))
    [1, u32le(id), u16le(len)] =>
      Some(Err(id~, payload_len=len.reinterpret_as_int()))
    [2, u32le(_), u16le(len)] =>
      Some(Event(payload_len=len.reinterpret_as_int()))
    _ => None
  }
}

///|
/// A decoded reply to a `Request`.
pub enum Response {
  IsATty(Bool)
  WinSize(rows~ : Int, cols~ : Int)
  Acknowledged
  Error(errno~ : Int)
} derive(Eq, Debug)

///|
/// Decode a control-connection reply against the request it answers and the
/// request id it was sent with. `None` marks a protocol violation: an event
/// frame on the control connection, a request id mismatch, or a payload
/// whose shape does not match the request.
fn Response::decode(
  request : Request,
  id~ : UInt,
  header : BytesView,
  payload : BytesView,
) -> Response? {
  guard FrameHeader::decode(header) is Some(header) else { return None }
  match header {
    Err(id=echoed, ..) if echoed == id => {
      guard payload is [i32le(code)] else { return None }
      Some(Error(errno=code))
    }
    Ok(id=echoed, ..) if echoed == id =>
      match request {
        IsATty(..) => {
          guard payload is [flag] else { return None }
          Some(IsATty(flag != 0))
        }
        WinSize(..) => {
          guard payload is [i32le(rows), i32le(cols)] else { return None }
          Some(WinSize(rows~, cols~))
        }
        EnterRawMode(..) | LeaveRawMode(..) | Watch(..) | Shutdown => {
          guard payload is [] else { return None }
          Some(Acknowledged)
        }
      }
    _ => None
  }
}

///|
/// A terminal event pushed by the sidecar on the event connection.
///
/// `Resize` is Unix-only (`SIGWINCH`, coalesced sidecar-side). On Windows
/// the sidecar instead streams the console's raw `INPUT_RECORD`s —
/// `InputRecords` carries whole records (`INPUT_RECORD_SIZE` bytes each),
/// and resizes arrive as `WINDOW_BUFFER_SIZE_EVENT` records within them.
pub enum Event {
  Resize(rows~ : Int, cols~ : Int)
  InputRecords(records~ : Bytes)
} derive(Eq, Debug)
