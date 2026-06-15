///|
#cfg(not(platform="windows"))
extern "C" fn open_controlling_terminal() -> @async/types.Fd = "moonbit_tty_open_controlling_terminal"

///|
/// Open the controlling terminal (`/dev/tty`) as one coordinated terminal
/// handle. The single bidirectional handle is wrapped as a raw stream and used
/// for both input and output.
#cfg(not(platform="windows"))
pub async fn Tty::open() -> Tty {
  let fd = open_controlling_terminal()
  if fd < 0 {
    @os_error.check_errno("Tty::open")
  }
  let terminal = @async/raw_fd.RawFdStream(fd)
  Tty::new(terminal, terminal)
}
