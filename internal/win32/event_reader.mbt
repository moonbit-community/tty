///|
pub(all) enum Event {
  Input(@public_input.InputEvent)
  Resize
} derive(Eq)

///|
/// What the console record source hands out: the sidecar forwards raw
/// `INPUT_RECORD`s and turns window size events into `Resize`.
pub(all) enum SourceEvent {
  Record(InputRecord)
  Resize
}

///|
struct EventReader {
  source : async () -> SourceEvent?
  byte_queue : @internal_io.ByteQueue
  decoder : @input.EventReader
  events : @async.Queue[Event]
  pending_surrogate : Ref[Int32]
  mouse_button_state : MouseButtonState
}

///|
pub fn EventReader::new(source : async () -> SourceEvent?) -> EventReader {
  let byte_queue = @internal_io.ByteQueue::new()
  {
    source,
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
  esc_timeout_ms : Int32,
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
  while (self.source)() is Some(event) {
    match event {
      Record(record) => self.read_record(record)
      Resize => {
        self.pending_surrogate.val = 0
        queue_event(self.events, Resize)
      }
    }
  }
  self.events.close()
}

///|
fn queue_event(events : @async.Queue[Event], event : Event) -> Unit {
  guard! (try! events.try_put(event))
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
pub extend Event with Eq::{equal, not_equal}
