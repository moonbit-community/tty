///|
/// Terminal window size in rows and columns.
pub struct WindowSize {
  rows : Int32
  cols : Int32
} derive(Eq, Debug)

///|
/// The visible terminal window size, as last reported by the sidecar.
pub fn Tty::window_size(self : Self) -> WindowSize raise @os_error.OSError {
  let (rows, cols) = self.sidecar_or_raise("Tty::window_size").size()
  { rows, cols, }
}

///|
pub extend WindowSize with Eq::{equal, not_equal}

///|
pub extend WindowSize with @debug.Debug::{to_repr}
