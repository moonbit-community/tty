///|
/// Opaque terminal state snapshot.
///
/// Capture a state with `Tty::get_state`, derive raw mode with
/// `State::make_raw`, and restore it with `Tty::set_state` or
/// `Tty::leave_raw_mode`.
#cfg(not(platform="windows"))
struct State(Bytes)

///|
#cfg(platform="windows")
struct State(Bytes, Win32InputMode)

///|
/// Capture the current terminal state for this handle.
pub fn Tty::get_state(self : Self) -> State raise @os_error.OSError {
  let state = self.new_state_snapshot()
  let rc = tty_get_state(self.input_fd, self.output_fd, state.0)
  if rc < 0 {
    @os_error.check_errno("Tty::get_state")
  }
  state
}

///|
/// Apply a terminal state and return the previous state.
pub fn Tty::set_state(
  self : Self,
  state : State,
) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  errdefer self.restore_input_protocol(old_state)
  self.restore_input_protocol(state)
  let rc = tty_set_state(self.input_fd, self.output_fd, state.0)
  if rc < 0 {
    ignore(tty_set_state(self.input_fd, self.output_fd, old_state.0))
    @os_error.check_errno("Tty::set_state")
  }
  old_state
}

///|
/// Derive a raw-mode state from this captured terminal state.
pub fn State::make_raw(self : Self) -> State {
  let raw = self.new_raw_state()
  tty_make_raw_state(self.0, raw.0)
  raw
}

///|
/// Enter raw mode and return the previous terminal state.
pub fn Tty::enter_raw_mode(self : Self) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let raw_state = old_state.make_raw()
  let rc = tty_set_state(self.input_fd, self.output_fd, raw_state.0)
  if rc < 0 {
    ignore(tty_set_state(self.input_fd, self.output_fd, old_state.0))
    @os_error.check_errno("Tty::enter_raw_mode")
  }
  old_state
}

///|
/// Restore a terminal state captured before or during raw mode.
pub fn Tty::leave_raw_mode(
  self : Self,
  state : State,
) -> Unit raise @os_error.OSError {
  self.restore_input_protocol(state)
  let rc = tty_set_state(self.input_fd, self.output_fd, state.0)
  if rc < 0 {
    @os_error.check_errno("Tty::leave_raw_mode")
  }
}

///|
/// Run an async callback with raw mode enabled.
///
/// The captured terminal state is restored on success, error, or cancellation.
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  let state = self.enter_raw_mode()
  defer self.leave_raw_mode(state)
  f()
}

///|
extern "c" fn get_sizeof_state() -> Int32 = "moonbit_tty_get_sizeof_state"

///|
let sizeof_state : Int32 = get_sizeof_state()

///|
#cfg(not(platform="windows"))
fn State::new() -> State {
  Bytes::make(sizeof_state, 0)
}

///|
#cfg(platform="windows")
fn State::new() -> State {
  State(Bytes::make(sizeof_state, 0), Unchecked)
}

///|
#cfg(platform="windows")
fn Tty::new_state_snapshot(self : Tty) -> State {
  State(State::new().0, self.win32_input_mode)
}

///|
#cfg(not(platform="windows"))
fn Tty::new_state_snapshot(_self : Tty) -> State {
  State::new()
}

///|
#cfg(platform="windows")
fn State::new_raw_state(self : State) -> State {
  State(State::new().0, self.1)
}

///|
#cfg(not(platform="windows"))
fn State::new_raw_state(_self : State) -> State {
  State::new()
}

///|
#cfg(platform="windows")
fn Tty::restore_input_protocol(
  self : Tty,
  state : State,
) -> Unit raise @os_error.OSError {
  self.restore_win32_input_mode(state.1)
}

///|
#cfg(not(platform="windows"))
fn Tty::restore_input_protocol(_self : Tty, _state : State) -> Unit {
  ()
}

///|
#borrow(state)
extern "c" fn tty_get_state(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
  state : Bytes,
) -> Int32 = "moonbit_tty_get_state"

///|
#borrow(state)
extern "c" fn tty_set_state(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
  state : Bytes,
) -> Int32 = "moonbit_tty_set_state"

///|
#borrow(state, raw)
extern "c" fn tty_make_raw_state(state : Bytes, raw : Bytes) -> Unit = "moonbit_tty_make_raw_state"
