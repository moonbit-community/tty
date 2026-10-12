///|
/// Terminal window size in rows and columns.
pub struct WindowSize {
  rows : Int32
  cols : Int32
} derive(Eq, Debug)

///|
/// Query the visible terminal window size.
pub fn Tty::window_size(self : Self) -> WindowSize raise @os_error.OSError {
  let rows = Ref(0)
  let cols = Ref(0)
  let rc = tty_get_window_size(self.output_fd, rows, cols)
  if rc < 0 {
    @os_error.check_errno("Tty::window_size")
  }
  { rows: rows.val, cols: cols.val, }
}

///|
#borrow(rows, cols)
extern "c" fn tty_get_window_size(
  fd : @async/types.Fd,
  rows : Ref[Int32],
  cols : Ref[Int32],
) -> Int32 = "moonbit_tty_get_window_size"

///|
pub extend WindowSize with Eq::{equal, not_equal}

///|
pub extend WindowSize with @debug.Debug::{to_repr}
