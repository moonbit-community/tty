///|
pub(all) enum Event {
  Input(@public_input.InputEvent)
  Resize
} derive(Eq)

///|
struct EventReader {
  input_fd : @async/types.Fd
  byte_queue : @internal_io.ByteQueue
  decoder : @input.EventReader
  resize_notifications : @async.Queue[Unit]
  mut pending_surrogate : Int32?
}

///|
pub fn EventReader::new(input_fd : @async/types.Fd) -> EventReader {
  let byte_queue = @internal_io.ByteQueue::new()
  {
    input_fd,
    byte_queue,
    decoder: @input.EventReader::new(byte_queue as &@async/io.Reader),
    resize_notifications: Queue(kind=DiscardLatest(1)),
    pending_surrogate: None,
  }
}

///|
pub fn EventReader::close(self : EventReader) -> Unit {
  self.byte_queue.close()
  self.resize_notifications.close(clear=true)
}

///|
pub async fn EventReader::read_event(
  self : EventReader,
  esc_timeout_ms~ : Int32 = 50,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.read_input_event(esc_timeout_ms)
  }
}

///|
pub async fn EventReader::read_internal_event(
  self : EventReader,
  esc_timeout_ms~ : Int32 = 50,
) -> @input.Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.decoder.read_event(esc_timeout_ms~)
  }
}

///|
async fn EventReader::read_input_event(
  self : EventReader,
  esc_timeout_ms : Int32,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      group.return_immediately(self.read_decoded_input_event(esc_timeout_ms))
    }
    try self.resize_notifications.get() catch {
      @aqueue.QueueAlreadyClosed => None
      err => raise err
    } noraise {
      _ => Some(Resize)
    }
  }
}

///|
async fn EventReader::read_decoded_input_event(
  self : EventReader,
  esc_timeout_ms : Int32,
) -> Event? {
  for ;; {
    match self.decoder.read_event(esc_timeout_ms~) {
      Input(event) => return Some(Input(event))
      CursorPosition(..) => ()
      Win32InputMode(_) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
async fn EventReader::read_records(self : EventReader) -> Unit {
  for ;; {
    let read_any = self.drain_records()
    @async.sleep(if read_any { 0 } else { 10 })
  }
}

///|
fn EventReader::drain_records(self : EventReader) -> Bool raise {
  let mut read_any = false
  for _ in 0..<64 {
    if read_console_input_record(self.input_fd) is Some(record) {
      read_any = true
      self.read_record(record)
    } else {
      return read_any
    }
  }
  read_any
}

///|
fn EventReader::read_record(
  self : EventReader,
  record : InputRecord,
) -> Unit raise {
  match record {
    Resize => ignore(self.resize_notifications.try_put(()))
    Ignored => ()
    Character(code_unit~, repeat_count~) =>
      if code_unit >= 0xd800 && code_unit <= 0xdbff {
        self.pending_surrogate = Some(code_unit)
      } else {
        let high = self.pending_surrogate
        self.pending_surrogate = None
        let codepoint = if code_unit >= 0xdc00 && code_unit <= 0xdfff {
          if high is Some(high) {
            0x10000 + (high - 0xd800) * 0x400 + code_unit - 0xdc00
          } else {
            0xfffd
          }
        } else {
          code_unit
        }
        let text : String = [codepoint.to_char().unwrap_or('\u{FFFD}')]
        for _ in 0..<repeat_count.max(1) {
          self.byte_queue.put_data(text)
        }
      }
  }
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
pub extend Event with Eq::{equal, not_equal}
