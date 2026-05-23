///|
/// Terminal window size in rows and columns.
pub struct WindowSize {
  rows : Int
  cols : Int
} derive(Eq)

///|
/// Query the visible terminal window size.
pub fn Tty::window_size(self : Self) -> WindowSize raise @os_error.OSError {
  let rows = Ref(0)
  let cols = Ref(0)
  let rc = tty_get_window_size(self.output.fd(), rows, cols)
  if rc < 0 {
    @os_error.check_errno("Tty::window_size")
  }
  { rows: rows.val, cols: cols.val }
}

///|
#borrow(rows, cols)
extern "c" fn tty_get_window_size(
  fd : @async/types.Fd,
  rows : Ref[Int],
  cols : Ref[Int],
) -> Int = "moonbit_tty_get_window_size"
