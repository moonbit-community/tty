///|
/// Raw-mode control on wasm: the pre-raw terminal state is captured and
/// restored inside the sidecar, so no `State` snapshot type exists on this
/// target (`get_state`/`set_state`/`State::make_raw` are native-only).
async fn Tty::set_raw_mode(self : Self, enter~ : Bool) -> Unit {
  let input = stdio_slot_or_invalid(self.input_fd)
  let output = stdio_slot_or_invalid(self.output_fd)
  let request : @sidecar.Request = if enter {
    EnterRawMode(input~, output~)
  } else {
    LeaveRawMode(input~, output~)
  }
  let context = if enter {
    "Tty::enter_raw_mode"
  } else {
    "Tty::leave_raw_mode"
  }
  match sidecar().call(request) {
    Acknowledged => ()
    Error(errno~) => raise @os_error.OSError(errno, context~)
    _ => raise @sidecar.ProtocolViolation
  }
}

///|
/// Enter raw mode. The sidecar captures the current terminal state on the
/// first call and restores it on `leave_raw_mode` — or on disconnect, if the
/// program dies while raw.
pub async fn Tty::enter_raw_mode(self : Self) -> Unit {
  self.set_raw_mode(enter=true)
}

///|
/// Restore the terminal state captured by `enter_raw_mode`.
pub async fn Tty::leave_raw_mode(self : Self) -> Unit {
  self.set_raw_mode(enter=false)
}

///|
/// Run an async callback with raw mode enabled.
///
/// The captured terminal state is restored on success or error.
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  self.enter_raw_mode()
  try f() catch {
    error => {
      self.leave_raw_mode()
      raise error
    }
  } noraise {
    value => {
      self.leave_raw_mode()
      value
    }
  }
}
