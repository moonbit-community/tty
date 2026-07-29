///|
/// Open the Windows console input device (`CONIN$`) as a synchronous,
/// non-overlapped handle. Returns an invalid handle on failure, with the
/// failure reason available through `GetLastError` (read by `@os_error`).
#cfg(platform="windows")
extern "C" fn open_console_input() -> @async/types.Fd = "moonbit_tty_open_console_input"

///|
/// Open the Windows console output device (`CONOUT$`) as a synchronous,
/// non-overlapped handle. Returns an invalid handle on failure, with the
/// failure reason available through `GetLastError` (read by `@os_error`).
#cfg(platform="windows")
extern "C" fn open_console_output() -> @async/types.Fd = "moonbit_tty_open_console_output"

///|
#cfg(platform="windows")
extern "C" fn console_handle_is_valid(fd : @async/types.Fd) -> Int = "moonbit_tty_handle_is_valid"

///|
/// Open the controlling terminal as one coordinated terminal handle.
///
/// `CONIN$` / `CONOUT$` are console (character) devices, not filesystem files,
/// so they are opened directly and wrapped as raw, non-overlapped handles via
/// `@async/raw_fd.RawFdStream`. `RawFdStream` detects the handle kind with
/// `GetFileType` (`CharDevice`) and never registers it for overlapped IO, which
/// is exactly what console devices need. Routing through `@async/fs.open`
/// instead would probe the handle with `GetFileInformationByHandle`, which fails
/// on console devices.
#cfg(platform="windows")
pub async fn open() -> @tty.Tty {
  let input_fd = open_console_input()
  if console_handle_is_valid(input_fd) == 0 {
    @os_error.check_errno("open")
  }
  let input = Terminal(@async/raw_fd.RawFdStream(input_fd))
  let output_fd = open_console_output()
  if console_handle_is_valid(output_fd) == 0 {
    input.0.close()
    @os_error.check_errno("open")
  }
  let output = Terminal(
    @async/raw_fd.RawFdStream(output_fd) catch {
      error => {
        input.0.close()
        raise error
      }
    },
  )
  @tty.Tty::new(input, output)
}
