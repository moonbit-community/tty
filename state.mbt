///|
/// Opaque terminal state snapshot.
///
/// Capture a state with `Tty::get_state`, derive raw mode with
/// `State::make_raw`, and restore it with `Tty::set_state` or
/// `Tty::leave_raw_mode`.
struct State(Bytes)

///|
/// Capture the current terminal state for this handle.
#cfg(target="native")
pub fn Tty::get_state(self : Self) -> State raise @os_error.OSError {
  let state = State::new()
  let rc = tty_get_state(self.input_fd, self.output_fd, state)
  if rc < 0 {
    @os_error.check_errno("Tty::get_state")
  }
  state
}

///|
/// Apply a terminal state and return the previous state.
#cfg(target="native")
pub fn Tty::set_state(
  self : Self,
  state : State,
) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let rc = tty_set_state(self.input_fd, self.output_fd, state)
  if rc < 0 {
    ignore(tty_set_state(self.input_fd, self.output_fd, old_state))
    @os_error.check_errno("Tty::set_state")
  }
  old_state
}

///|
/// Derive a raw-mode state from this captured terminal state.
#cfg(target="native")
pub fn State::make_raw(self : Self) -> State {
  let raw = State::new()
  tty_make_raw_state(self, raw)
  raw
}

///|
/// Enter raw mode and return the previous terminal state.
#cfg(target="native")
pub fn Tty::enter_raw_mode(self : Self) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let raw_state = old_state.make_raw()
  let rc = tty_set_state(self.input_fd, self.output_fd, raw_state)
  if rc < 0 {
    ignore(tty_set_state(self.input_fd, self.output_fd, old_state))
    @os_error.check_errno("Tty::enter_raw_mode")
  }
  old_state
}

///|
/// Restore a terminal state captured before or during raw mode.
#cfg(target="native")
pub fn Tty::leave_raw_mode(
  self : Self,
  state : State,
) -> Unit raise @os_error.OSError {
  let rc = tty_set_state(self.input_fd, self.output_fd, state)
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
#cfg(target="native")
extern "c" fn get_sizeof_state() -> Int32 = "moonbit_tty_get_sizeof_state"

///|
#cfg(target="native")
let sizeof_state : Int32 = get_sizeof_state()

///|
#cfg(target="native")
fn State::new() -> State {
  Bytes::make(sizeof_state, 0)
}

///|
#cfg(target="native")
#borrow(state)
extern "c" fn tty_get_state(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
  state : State,
) -> Int32 = "moonbit_tty_get_state"

///|
#cfg(target="native")
#borrow(state)
extern "c" fn tty_set_state(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
  state : State,
) -> Int32 = "moonbit_tty_set_state"

///|
#cfg(target="native")
#borrow(state, raw)
extern "c" fn tty_make_raw_state(state : State, raw : State) -> Unit = "moonbit_tty_make_raw_state"
