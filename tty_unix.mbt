///|
#cfg(not(platform="windows"))
extern "C" fn open_controlling_terminal() -> @async/types.Fd = "moonbit_tty_open_controlling_terminal"

///|
#warnings("-14")
#cfg(not(platform="windows"))
priv struct ControllingTerminal {
  raw : @async/raw_fd.RawFd
  read_buf : @async/io.ReaderBuffer
}

///|
#warnings("-14")
#cfg(not(platform="windows"))
async fn ControllingTerminal::open() -> ControllingTerminal {
  let fd = open_controlling_terminal()
  if fd < 0 {
    @os_error.check_errno("Tty::open")
  }
  ControllingTerminal::{
    raw: @async/raw_fd.RawFd::RawFd(fd),
    read_buf: @async/io.ReaderBuffer::new(),
  }
}

///|
#cfg(not(platform="windows"))
impl @async/io.Reader for ControllingTerminal with _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  self.raw.read(buf, offset~, max_len~)
}

///|
#cfg(not(platform="windows"))
impl @async/io.Reader for ControllingTerminal with _get_internal_buffer(self) {
  self.read_buf
}

///|
#cfg(not(platform="windows"))
impl @async/io.Writer for ControllingTerminal with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  self.raw.write(buf, offset~, len~)
}

///|
#cfg(not(platform="windows"))
impl Reader for ControllingTerminal with fd(self) {
  self.raw.fd
}

///|
#cfg(not(platform="windows"))
impl Reader for ControllingTerminal with close(self) {
  self.raw.close()
}

///|
#cfg(not(platform="windows"))
impl Writer for ControllingTerminal with fd(self) {
  self.raw.fd
}

///|
#cfg(not(platform="windows"))
impl Writer for ControllingTerminal with close(self) {
  self.raw.close()
}

///|
#cfg(not(platform="windows"))
/// Open the controlling terminal as one coordinated terminal handle.
pub async fn Tty::open() -> Tty {
  let terminal = ControllingTerminal::open()
  Tty::new(terminal, terminal)
}

///|
#cfg(platform="windows")
/// Open the controlling terminal as one coordinated terminal handle.
pub async fn Tty::open() -> Tty {
  let file = @async/fs.open("/dev/tty", mode=ReadWrite)
  Tty::new(file, file)
}
