///|
/// Whether terminal input handles may be Windows consoles, which deliver typed
/// input records instead of a byte stream.
#cfg(platform="windows")
const ConsoleRecordInput : Bool = true

///|
#cfg(not(platform="windows"))
const ConsoleRecordInput : Bool = false

///|
/// Console input source for a Windows console input handle.
///
/// `@win32.ConsoleReader` serializes console input records into VT input bytes
/// for the decoder and reports resize out-of-band. Every other handle is
/// already a byte stream and has no console source.
fn console_input_reader(input_fd : @async/types.Fd) -> @win32.ConsoleReader? {
  if ConsoleRecordInput && tty_isatty(input_fd) > 0 {
    Some(@win32.ConsoleReader::new(input_fd))
  } else {
    None
  }
}

///|
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int32,
) -> Event {
  guard self.console is Some(console) else {
    return self.read_byte_stream_event(esc_timeout_ms)
  }
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      group.return_immediately(
        read_decoded_input_event(self.reader, esc_timeout_ms),
      )
    }
    self.read_console_resize_event(console)
  }
}

///|
/// Wait for a console resize notification and report the visible window size.
///
/// The window buffer size record carries the screen buffer size, which in
/// classic conhost includes scrollback rows, so the visible size is queried
/// instead.
async fn Tty::read_console_resize_event(
  self : Self,
  console : @win32.ConsoleReader,
) -> Event {
  for ;; {
    console.wait_resize()
    try self.window_size() catch {
      _ => ()
    } noraise {
      size => return Resize(size)
    }
  }
}
