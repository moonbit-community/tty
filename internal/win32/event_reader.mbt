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
  events : @async.Queue[Event]
  pending_surrogate : Ref[Int]
  mouse_button_state : MouseButtonState
}

///|
pub fn EventReader::new(input_fd : @async/types.Fd) -> EventReader {
  let byte_queue = @internal_io.ByteQueue::new()
  {
    input_fd,
    byte_queue,
    decoder: @input.EventReader::new(byte_queue as &@async/io.Reader),
    events: Queue(kind=Unbounded),
    pending_surrogate: Ref(0),
    mouse_button_state: MouseButtonState::new(),
  }
}

///|
pub fn EventReader::close(self : EventReader) -> Unit {
  self.byte_queue.close()
  self.events.close(clear=true)
}

///|
pub async fn EventReader::read_event(
  self : EventReader,
  esc_timeout_ms? : Int = 50,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.read_input_event(esc_timeout_ms)
  }
}

///|
pub async fn EventReader::read_internal_event(
  self : EventReader,
  esc_timeout_ms? : Int = 50,
) -> @input.Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.decoder.read_event(esc_timeout_ms~)
  }
}

///|
async fn EventReader::read_input_event(
  self : EventReader,
  esc_timeout_ms : Int,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      group.return_immediately(self.read_decoded_input_event(esc_timeout_ms))
    }
    try self.events.get() catch {
      @aqueue.QueueAlreadyClosed => None
      err => raise err
    } noraise {
      event => Some(event)
    }
  }
}

///|
async fn EventReader::read_decoded_input_event(
  self : EventReader,
  esc_timeout_ms : Int,
) -> Event? {
  for ;; {
    match self.decoder.read_event(esc_timeout_ms~) {
      Input(event) => return Some(Input(event))
      CursorPosition(..) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
async fn EventReader::read_records(self : EventReader) -> Unit {
  for ;; {
    if !self.drain_records() {
      @async.sleep(10)
    }
  }
}

///|
fn EventReader::drain_records(self : EventReader) -> Bool raise {
  let mut read_any = false
  for ;; {
    if read_console_input_record(self.input_fd) is Some(record) {
      read_any = true
      self.read_record(record)
    } else {
      return read_any
    }
  }
}

///|
fn queue_event(events : @async.Queue[Event], event : Event) -> Unit {
  guard (try! events.try_put(event))
}

///|
fn EventReader::read_record(self : EventReader, record : InputRecord) -> Unit {
  match record {
    Key(record) => self.read_key_record(record)
    Mouse(record) => self.read_mouse_record(record)
    WindowBufferSize(_) => {
      self.pending_surrogate.val = 0
      queue_event(self.events, Resize)
    }
    Focus(focus_set) => {
      self.pending_surrogate.val = 0
      if focus_set {
        queue_event(self.events, Input(FocusIn))
      } else {
        queue_event(self.events, Input(FocusOut))
      }
    }
    Unsupported(_) => self.pending_surrogate.val = 0
  }
}

///|
fn EventReader::read_key_record(self : EventReader, record : KeyRecord) -> Unit {
  if !record.is_down() {
    return
  }
  if !record.text_uses_decoder() {
    return self.queue_key_input(record)
  }
  match record.text(self.pending_surrogate) {
    Some(text) =>
      for _ in 0..<record.repeat_count() {
        self.byte_queue.put_data(text)
      }
    None => self.queue_key_input(record)
  }
}

///|
fn EventReader::queue_key_input(self : EventReader, record : KeyRecord) -> Unit {
  match record.input(self.pending_surrogate) {
    Some(input) =>
      for _ in 0..<record.repeat_count() {
        queue_event(self.events, Input(input))
      }
    None => ()
  }
}

///|
fn EventReader::read_mouse_record(
  self : EventReader,
  record : MouseRecord,
) -> Unit {
  self.pending_surrogate.val = 0
  match self.mouse_button_state.input_event(record) {
    Some(input) => queue_event(self.events, Input(input))
    None => ()
  }
}

///|
extern "c" fn sizeof_input_record() -> Int = "moonbit_tty_get_sizeof_input_record"

///|
let sizeof_win32_input_record : Int = sizeof_input_record()

///|
#borrow(record)
extern "c" fn read_console_input_record_ffi(
  fd : @async/types.Fd,
  record : Bytes,
) -> Int = "moonbit_tty_read_console_input_record"

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
