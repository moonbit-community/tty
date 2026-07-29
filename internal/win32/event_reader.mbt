///|
/// Console event reader that polls the console input buffer through C
/// (`ReadConsoleInputW` behind `moonbit_tty_read_console_input_record`).
struct EventReader {
  router : RecordRouter
  input_fd : @async/types.Fd
}

///|
pub fn EventReader::new(input_fd : @async/types.Fd) -> EventReader {
  { router: RecordRouter(), input_fd }
}

///|
pub fn EventReader::close(self : EventReader) -> Unit {
  self.router.close()
}

///|
pub async fn EventReader::read_event(
  self : EventReader,
  esc_timeout_ms? : Int = 50,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.router.read_input_event(esc_timeout_ms)
  }
}

///|
pub async fn EventReader::read_internal_event(
  self : EventReader,
  esc_timeout_ms? : Int = 50,
) -> @input.Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    self.router.decoder.read_event(esc_timeout_ms~)
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
      self.router.route(record)
    } else {
      return read_any
    }
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
