///|
/// Opaque terminal state snapshot.
///
/// Capture a state with `Tty::get_state`, derive raw mode with
/// `State::make_raw`, and restore it with `Tty::set_state` or
/// `Tty::leave_raw_mode`.
struct State(Bytes)

///|
/// Capture the current terminal state from the input side of this handle.
pub fn Tty::get_state(self : Self) -> State raise @os_error.OSError {
  let state = State::new()
  let rc = tty_get_state(self.input.fd(), state)
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
  let rc = tty_set_state(self.input.fd(), state)
  if rc < 0 {
    @os_error.check_errno("Tty::set_state")
  }
  old_state
}

///|
/// Derive a raw-mode state from this captured terminal state.
pub fn State::make_raw(self : Self) -> State {
  let raw = State::new()
  tty_make_raw_state(self, raw)
  raw
}

///|
/// Enter raw mode and return the previous terminal state.
pub fn Tty::enter_raw_mode(self : Self) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let raw_state = old_state.make_raw()
  let rc = tty_set_state(self.input.fd(), raw_state)
  if rc < 0 {
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
  let rc = tty_set_state(self.input.fd(), state)
  if rc < 0 {
    @os_error.check_errno("Tty::leave_raw_mode")
  }
}

///|
/// Run an async callback with raw mode enabled.
///
/// The captured terminal state is restored on success or error.
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  let state = self.enter_raw_mode()
  try f() catch {
    error => {
      self.leave_raw_mode(state)
      raise error
    }
  } noraise {
    value => {
      self.leave_raw_mode(state)
      value
    }
  }
}

///|
extern "c" fn get_sizeof_state() -> Int = "moonbit_tty_get_sizeof_state"

///|
let sizeof_state : Int = get_sizeof_state()

///|
fn State::new() -> State {
  Bytes::make(sizeof_state, 0)
}

///|
#borrow(state)
extern "c" fn tty_get_state(fd : @async/types.Fd, state : State) -> Int = "moonbit_tty_get_state"

///|
#borrow(state)
extern "c" fn tty_set_state(fd : @async/types.Fd, state : State) -> Int = "moonbit_tty_set_state"

///|
#borrow(state, raw)
extern "c" fn tty_make_raw_state(state : State, raw : State) -> Unit = "moonbit_tty_make_raw_state"
