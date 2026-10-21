///|
/// Whether terminal input handles may be Windows consoles, which deliver typed
/// input records instead of a byte stream.
#cfg(platform="windows")
const ConsoleRecordInput : Bool = true

///|
#cfg(not(platform="windows"))
const ConsoleRecordInput : Bool = false

///|
/// Byte source for the terminal input decoder.
///
/// Windows console input handles are read through `@win32.ConsoleReader`,
/// which serializes their input records into VT input bytes. Every other
/// handle is already a byte stream.
fn input_byte_source(
  input : &Reader,
  input_fd : @async/types.Fd,
) -> &@async/io.Reader {
  if ConsoleRecordInput && tty_isatty(input_fd) > 0 {
    @win32.ConsoleReader::new(input_fd) as &@async/io.Reader
  } else {
    input as &@async/io.Reader
  }
}

///|
/// Root event for a decoded text area size report.
///
/// `@win32.ConsoleReader` encodes console window buffer size records as text
/// area size reports. The record carries the screen buffer size, which in
/// classic conhost includes scrollback rows, so the visible size is queried
/// again instead of trusting the payload.
///
/// Unix terminals send the report only in reply to an XTWINOPS query, which
/// the root package does not issue; resize comes from `SIGWINCH` instead.
fn Tty::text_area_size_event(self : Self) -> Event? {
  guard ConsoleRecordInput else { return None }
  try self.window_size() catch {
    _ => None
  } noraise {
    size => Some(Resize(size))
  }
}
