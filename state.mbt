///|
/// Terminal State
struct State(Bytes)

///|
pub fn Input::get_state(self : Self) -> State raise @os_error.OSError {
  let state = State::new()
  let rc = tty_get_state(self.fd(), state)
  if rc < 0 {
    @os_error.check_errno("Input::get_state")
  }
  state
}

///|
pub fn Input::set_state(
  self : Self,
  state : State,
) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let rc = tty_set_state(self.fd(), state)
  if rc < 0 {
    @os_error.check_errno("Input::set_state")
  }
  old_state
}

///|
pub fn State::make_raw(self : Self) -> State {
  let raw = State::new()
  tty_make_raw_state(self, raw)
  raw
}

///|
pub fn Input::enter_raw_mode(self : Self) -> State raise @os_error.OSError {
  let old_state = self.get_state()
  let raw_state = old_state.make_raw()
  let rc = tty_set_state(self.fd(), raw_state)
  if rc < 0 {
    @os_error.check_errno("Input::enter_raw_mode")
  }
  old_state
}

///|
pub fn Input::leave_raw_mode(
  self : Self,
  state : State,
) -> Unit raise @os_error.OSError {
  let rc = tty_set_state(self.fd(), state)
  if rc < 0 {
    @os_error.check_errno("Input::leave_raw_mode")
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
