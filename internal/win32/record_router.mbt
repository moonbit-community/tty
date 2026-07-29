///|
// Package imports are shared across target-specific files: the sidecar
// protocol is only touched by the wasm record source, the os_error/fd
// surface only by the native console reader.
let _shared_import_anchor : Unit = {
  ignore(@sidecar.INPUT_RECORD_SIZE)
  ignore(@os_error.errno_ENOTDIR)
}

///|
let _fd_type_import_anchor : @async/types.Fd? = None

///|
pub(all) enum Event {
  Input(@public_input.InputEvent)
  Resize
} derive(Eq)

///|
/// Routes Win32 console input records into terminal events, independent of
/// where the records come from: the native reader polls the console through
/// C, the wasm backend receives records streamed by the sidecar.
priv struct RecordRouter {
  byte_queue : @internal_io.ByteQueue
  decoder : @input.EventReader
  events : @async.Queue[Event]
  pending_surrogate : Ref[Int]
  mouse_button_state : MouseButtonState
}

///|
fn RecordRouter::RecordRouter() -> RecordRouter {
  let byte_queue = @internal_io.ByteQueue::new()
  {
    byte_queue,
    decoder: @input.EventReader::new(byte_queue as &@async/io.Reader),
    events: Queue(kind=Unbounded),
    pending_surrogate: Ref(0),
    mouse_button_state: MouseButtonState::new(),
  }
}

///|
fn RecordRouter::close(self : RecordRouter) -> Unit {
  self.byte_queue.close()
  self.events.close(clear=true)
}

///|
async fn RecordRouter::read_input_event(
  self : RecordRouter,
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
async fn RecordRouter::read_decoded_input_event(
  self : RecordRouter,
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
fn queue_event(events : @async.Queue[Event], event : Event) -> Unit {
  guard (try! events.try_put(event))
}

///|
fn RecordRouter::route(self : RecordRouter, record : InputRecord) -> Unit {
  match record {
    Key(record) => self.route_key_record(record)
    Mouse(record) => self.route_mouse_record(record)
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
fn RecordRouter::route_key_record(
  self : RecordRouter,
  record : KeyRecord,
) -> Unit {
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
fn RecordRouter::queue_key_input(
  self : RecordRouter,
  record : KeyRecord,
) -> Unit {
  match record.input(self.pending_surrogate) {
    Some(input) =>
      for _ in 0..<record.repeat_count() {
        queue_event(self.events, Input(input))
      }
    None => ()
  }
}

///|
fn RecordRouter::route_mouse_record(
  self : RecordRouter,
  record : MouseRecord,
) -> Unit {
  self.pending_surrogate.val = 0
  match self.mouse_button_state.input_event(record) {
    Some(input) => queue_event(self.events, Input(input))
    None => ()
  }
}
