///|
/// Size of a raw `INPUT_RECORD`: a 16-bit event type, padding, and a
/// 16-byte event union.
const INPUT_RECORD_SIZE : Int32 = 20

///|
/// Byte reader over a stream of raw Windows console `INPUT_RECORD`s, each
/// `INPUT_RECORD_SIZE` bytes, as forwarded by the tty sidecar.
///
/// Console input is typed records rather than a byte stream. `RecordReader`
/// serializes them into VT input bytes with `RecordEncoder`, so the shared byte
/// decoder sees keys, mouse, and focus in record order. Window resizes do not
/// travel in the record stream: the sidecar reports them out of band by
/// interrupting the read, see `internal/sidecar`.
#warnings("-14")
struct RecordReader {
  records : &@async/io.Reader
  encoder : RecordEncoder
  read_buf : @async/io.ReaderBuffer
  // A record received so far; kept on the reader because a read can be
  // cancelled, or interrupted by a sidecar resize, in the middle of a record.
  record : FixedArray[Byte]
  mut record_len : Int32
  // Encoded bytes not yet handed to the caller.
  mut pending : Bytes
  mut pending_offset : Int32
}

///|
/// Create a byte reader over a raw console record stream.
#warnings("-14")
pub fn RecordReader::new(records : &@async/io.Reader) -> RecordReader {
  {
    records,
    encoder: RecordEncoder::new(),
    read_buf: @async/io.ReaderBuffer::new(),
    record: FixedArray::make(INPUT_RECORD_SIZE, b'\x00'),
    record_len: 0,
    pending: b"",
    pending_offset: 0,
  }
}

///|
/// One whole raw record, or `None` at a clean end of the stream.
async fn RecordReader::read_raw_record(self : RecordReader) -> Bytes? {
  while self.record_len < INPUT_RECORD_SIZE {
    let n = self.records.read(
      self.record,
      offset=self.record_len,
      max_len=INPUT_RECORD_SIZE - self.record_len,
    )
    if n == 0 {
      if self.record_len == 0 {
        return None
      }
      fail("console input closed in the middle of a record")
    }
    self.record_len += n
  }
  self.record_len = 0
  Some(Bytes::from_array(self.record[:]))
}

///|
pub impl @async/io.Reader for RecordReader with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @async/io.Reader for RecordReader with fn _direct_read(
  self,
  dst,
  offset~,
  max_len~,
) {
  if max_len <= 0 {
    return 0
  }
  for ;; {
    let available = self.pending.length() - self.pending_offset
    if available > 0 {
      let len = if available < max_len { available } else { max_len }
      for i in 0..<len {
        dst[offset + i] = self.pending[self.pending_offset + i]
      }
      self.pending_offset += len
      return len
    }
    guard self.read_raw_record() is Some(record) else { return 0 }
    // Records that encode to nothing, such as key releases, loop for the next.
    let out = @buffer.Buffer()
    self.encoder.encode(InputRecord::parse(record), out)
    self.pending = out.to_bytes()
    self.pending_offset = 0
  }
}

///|
pub extend RecordReader with @async/io.Reader::{
  _direct_read,
  _get_internal_buffer,
  drop,
  read,
  read_all,
  read_exactly,
  read_some,
  read_until,
}
