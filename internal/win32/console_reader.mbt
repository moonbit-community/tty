///|
/// Byte reader over a Windows console input handle.
///
/// `ReadConsoleInputW` returns typed input records rather than a byte stream.
/// `ConsoleReader` serializes them into VT input bytes with `RecordEncoder` so
/// the shared byte decoder sees keys, mouse, focus, and resize in record order.
///
/// Reads poll the console input buffer with non-blocking peek/read calls and
/// sleep briefly when it is empty. Records are encoded synchronously as soon
/// as they are read, so cancelling a read (for example the decoder's escape
/// timeout) can only interrupt the sleep and never drops a consumed record.
#warnings("-14")
struct ConsoleReader {
  input_fd : @async/types.Fd
  encoder : RecordEncoder
  read_buf : @async/io.ReaderBuffer
  mut pending : Bytes
  mut pending_offset : Int32
}

///|
/// Create a reader over a console input handle. The reader does not own the
/// handle and does not close it.
#warnings("-14")
pub fn ConsoleReader::new(input_fd : @async/types.Fd) -> ConsoleReader {
  {
    input_fd,
    encoder: RecordEncoder::new(),
    read_buf: @async/io.ReaderBuffer::new(),
    pending: b"",
    pending_offset: 0,
  }
}

///|
/// Drain every record available now and encode them into `pending`.
fn ConsoleReader::fill(self : ConsoleReader) -> Unit raise {
  let vt_input = console_input_vt_enabled(self.input_fd)
  let out = @buffer.Buffer()
  for ;; {
    guard read_console_input_record(self.input_fd) is Some(record) else {
      break
    }
    self.encoder.encode(record, vt_input~, out)
  }
  self.pending = out.to_bytes()
  self.pending_offset = 0
}

///|
pub impl @async/io.Reader for ConsoleReader with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @async/io.Reader for ConsoleReader with fn _direct_read(
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
    self.fill()
    if self.pending.length() == 0 {
      @async.sleep(10)
    }
  }
}

///|
pub extend ConsoleReader with @async/io.Reader::{
  _direct_read,
  _get_internal_buffer,
  drop,
  read,
  read_all,
  read_exactly,
  read_some,
  read_until,
}

///|
extern "c" fn sizeof_input_record() -> Int32 = "moonbit_tty_get_sizeof_input_record"

///|
let sizeof_win32_input_record : Int32 = sizeof_input_record()

///|
#borrow(record)
extern "c" fn read_console_input_record_ffi(
  fd : @async/types.Fd,
  record : Bytes,
) -> Int32 = "moonbit_tty_read_console_input_record"

///|
fn read_console_input_record(fd : @async/types.Fd) -> InputRecord? raise {
  let record = Bytes::make(sizeof_win32_input_record, 0)
  let rc = read_console_input_record_ffi(fd, record)
  if rc < 0 {
    @os_error.check_errno("ReadConsoleInputW")
  }
  if rc == 0 {
    None
  } else {
    Some(InputRecord::parse(record))
  }
}

///|
extern "c" fn console_input_vt_enabled_ffi(fd : @async/types.Fd) -> Int32 = "moonbit_tty_console_input_vt_enabled"

///|
/// Whether the console input mode has `ENABLE_VIRTUAL_TERMINAL_INPUT`.
fn console_input_vt_enabled(fd : @async/types.Fd) -> Bool raise {
  let rc = console_input_vt_enabled_ffi(fd)
  if rc < 0 {
    @os_error.check_errno("GetConsoleMode")
  }
  rc > 0
}
