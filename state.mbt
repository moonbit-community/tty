///|
/// Whether the terminal was in raw mode before an `enter_raw_mode` call;
/// `leave_raw_mode` restores exactly that, so nested scopes compose as long
/// as each caller restores the state it captured.
struct State(Bool)

///|
/// The controlling terminal backend for this handle, or `OSError(ENOTSUP)` for
/// stream handles, which have no terminal state of their own.
fn Tty::terminal_or_raise(
  self : Self,
  context : String,
) -> Terminal raise @os_error.OSError {
  guard self.terminal is Some(terminal) else {
    raise OSError(@os_error.errno_ENOTSUP, context~)
  }
  terminal
}

///|
/// Enter raw mode: no echo, no line buffering, no signal keys, VT input.
/// Returns the previous state for `leave_raw_mode`.
pub async fn Tty::enter_raw_mode(self : Self) -> State {
  let terminal = self.terminal_or_raise("Tty::enter_raw_mode")
  let state = State(terminal.is_raw())
  terminal.set_raw(true)
  state
}

///|
/// Restore the state captured by `enter_raw_mode`: leaves raw mode unless
/// the terminal was already raw when that call was made.
pub async fn Tty::leave_raw_mode(self : Self, state : State) -> Unit {
  let terminal = self.terminal_or_raise("Tty::leave_raw_mode")
  if !state.0 {
    terminal.set_raw(false)
  }
}

///|
/// Run an async callback with raw mode enabled.
///
/// The captured state is restored on success, error, or cancellation.
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  let state = self.enter_raw_mode()
  defer self.restore_raw_mode(state)
  f()
}

///|
/// Restoring the terminal must happen even while the task is being
/// cancelled, so the sidecar command is sent under `protect_from_cancel`.
async fn Tty::restore_raw_mode(self : Self, state : State) -> Unit nocancel {
  @async.protect_from_cancel(() => self.leave_raw_mode(state))
}
