///|
#cfg(platform="windows")
priv enum WindowsInput {
  ByteStream
  Console(
    input_fd~ : @async/types.Fd,
    byte_queue~ : @internal_io.ByteQueue,
    events~ : @async.Queue[Event],
    pending_surrogate~ : Ref[Int],
    mouse_button_state~ : @win32.MouseButtonState
  )
}

///|
#cfg(platform="windows")
fn WindowsInput::new(input_fd : @async/types.Fd) -> WindowsInput {
  if tty_isatty(input_fd) > 0 {
    WindowsInput::console(input_fd)
  } else {
    ByteStream
  }
}

///|
#cfg(platform="windows")
fn WindowsInput::console(input_fd : @async/types.Fd) -> WindowsInput {
  let byte_queue = @internal_io.ByteQueue::new()
  Console(
    input_fd~,
    byte_queue~,
    events=Queue(kind=Unbounded),
    pending_surrogate=Ref(0),
    mouse_button_state=@win32.MouseButtonState::new(),
  )
}

///|
#cfg(platform="windows")
fn WindowsInput::event_reader(
  self : WindowsInput,
  fallback : &@async/io.Reader,
) -> @input.EventReader {
  match self {
    ByteStream => @input.EventReader::new(fallback)
    Console(byte_queue~, ..) =>
      @input.EventReader::new(byte_queue as &@async/io.Reader)
  }
}

///|
#cfg(platform="windows")
fn WindowsInput::close(self : WindowsInput) -> Unit {
  match self {
    ByteStream => ()
    Console(byte_queue~, events~, ..) => {
      byte_queue.close()
      events.close(clear=true)
    }
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_win32_console_event(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  match self.input_backend {
    Console(..) => self.read_console_event(esc_timeout_ms)
    ByteStream => self.read_decoded_input_event(esc_timeout_ms)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  match self.input_backend {
    Console(..) =>
      @async.with_task_group() <| group => {
        group.spawn_bg(no_wait=true) <| () => { self.read_records() }
        self.reader.read_event(esc_timeout_ms~)
      }
    ByteStream => self.reader.read_event(esc_timeout_ms~)
  }
}

///|
#cfg(not(platform="windows"))
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}

///|
#cfg(platform="windows")
async fn Tty::read_console_event(self : Self, esc_timeout_ms : Int) -> Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.read_console_input_event(esc_timeout_ms)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_console_input_event(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  match self.input_backend {
    Console(events~, ..) =>
      @async.with_task_group() <| group => {
        group.spawn_bg(no_wait=true) <| () => {
          group.return_immediately(
            self.read_decoded_input_event(esc_timeout_ms),
          )
        }
        events.get()
      }
    ByteStream => self.read_decoded_input_event(esc_timeout_ms)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_records(self : Self) -> Unit {
  match self.input_backend {
    Console(input_fd~, ..) =>
      for ;; {
        if !self.drain_records(input_fd) {
          @async.sleep(10)
        }
      }
    ByteStream => ()
  }
}

///|
#cfg(platform="windows")
fn Tty::drain_records(self : Self, input_fd : @async/types.Fd) -> Bool raise {
  let mut read_any = false
  for ;; {
    match win32_read_console_input_record(input_fd) {
      None => return read_any
      Some(record) => {
        read_any = true
        self.read_record(record)
      }
    }
  }
}

///|
#cfg(platform="windows")
fn queue_console_event(events : @async.Queue[Event], event : Event) -> Unit {
  try events.try_put(event) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
#cfg(platform="windows")
fn Tty::read_record(self : Self, record : @win32.InputRecord) -> Unit {
  match self.input_backend {
    Console(events~, pending_surrogate~, ..) =>
      match record {
        Key(record) => self.read_key_record(record)
        Mouse(record) => self.read_mouse_record(record)
        WindowBufferSize(_) => {
          pending_surrogate.val = 0
          try self.window_size() catch {
            _ => ()
          } noraise {
            size => queue_console_event(events, Resize(size))
          }
        }
        Focus(focus_set) => {
          pending_surrogate.val = 0
          if focus_set {
            queue_console_event(events, Input(FocusIn))
          } else {
            queue_console_event(events, Input(FocusOut))
          }
        }
        Unsupported(_) => pending_surrogate.val = 0
      }
    ByteStream => ()
  }
}

///|
#cfg(platform="windows")
fn Tty::read_key_record(self : Self, record : @win32.KeyRecord) -> Unit {
  match self.input_backend {
    Console(byte_queue~, pending_surrogate~, ..) => {
      if !record.is_down() {
        return
      }
      if !record.text_uses_decoder() {
        return self.queue_key_input(record)
      }
      match record.text(pending_surrogate) {
        Some(text) =>
          for _ in 0..<record.repeat_count() {
            byte_queue.put_data(text)
          }
        None => self.queue_key_input(record)
      }
    }
    ByteStream => ()
  }
}

///|
#cfg(platform="windows")
fn Tty::queue_key_input(self : Self, record : @win32.KeyRecord) -> Unit {
  match self.input_backend {
    Console(events~, pending_surrogate~, ..) =>
      match record.input(pending_surrogate) {
        Some(input) =>
          for _ in 0..<record.repeat_count() {
            queue_console_event(events, Input(input))
          }
        None => ()
      }
    ByteStream => ()
  }
}

///|
#cfg(platform="windows")
fn Tty::read_mouse_record(self : Self, record : @win32.MouseRecord) -> Unit {
  match self.input_backend {
    Console(events~, pending_surrogate~, mouse_button_state~, ..) => {
      pending_surrogate.val = 0
      match mouse_button_state.input_event(record) {
        Some(input) => queue_console_event(events, Input(input))
        None => ()
      }
    }
    ByteStream => ()
  }
}

///|
#cfg(platform="windows")
extern "c" fn win32_sizeof_input_record() -> Int = "moonbit_tty_get_sizeof_input_record"

///|
#cfg(platform="windows")
let sizeof_win32_input_record : Int = win32_sizeof_input_record()

///|
#borrow(record)
#cfg(platform="windows")
extern "c" fn win32_read_console_input_record_ffi(
  fd : @async/types.Fd,
  record : Bytes,
) -> Int = "moonbit_tty_read_console_input_record"

///|
#cfg(platform="windows")
fn win32_read_console_input_record(
  fd : @async/types.Fd,
) -> @win32.InputRecord? raise {
  let record = Bytes::make(sizeof_win32_input_record, 0)
  let rc = win32_read_console_input_record_ffi(fd, record)
  if rc < 0 {
    @os_error.check_errno("ReadConsoleInputW")
  }
  if rc == 0 {
    None
  } else {
    Some(@win32.InputRecord::parse(record))
  }
}
