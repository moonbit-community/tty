///|
/// Open the controlling terminal through a sidecar process (see
/// `sidecar/README.md`), found via the `TTY_SIDECAR` environment variable or
/// an embedded executable. The sidecar serves as both input and output.
#cfg(target="wasm")
pub async fn Tty::open() -> Tty {
  let sidecar = @sidecar.open()
  Tty::from_streams(sidecar, sidecar, sidecar=Some(sidecar))
}

///|
/// The sidecar that backs this handle, or `OSError(ENOTSUP)` for stream
/// handles, which have no terminal of their own on wasm.
#cfg(target="wasm")
fn Tty::sidecar_or_raise(
  self : Self,
  context : String,
) -> @sidecar.Sidecar raise @os_error.OSError {
  guard self.sidecar is Some(sidecar) else {
    raise OSError(@os_error.errno_ENOTSUP, context~)
  }
  sidecar
}

///|
#cfg(target="wasm")
impl Fd for @sidecar.Sidecar with fn fd(_) {
  raise @os_error.OSError(@os_error.errno_ENOTSUP, context="Tty::fd")
}

///|
#cfg(target="wasm")
impl Reader for @sidecar.Sidecar with fn close(self) {
  self.close()
}

///|
#cfg(target="wasm")
impl Writer for @sidecar.Sidecar with fn close(self) {
  self.close()
}

///|
/// Query the visible terminal window size, as last reported by the sidecar.
#cfg(target="wasm")
pub fn Tty::window_size(self : Self) -> WindowSize raise @os_error.OSError {
  let (rows, cols) = self.sidecar_or_raise("Tty::window_size").size()
  { rows, cols, }
}

///|
/// Capture the current terminal state for this handle. On wasm the state is
/// just whether raw mode is on.
#cfg(target="wasm")
pub fn Tty::get_state(self : Self) -> State raise @os_error.OSError {
  if self.sidecar_or_raise("Tty::get_state").is_raw() {
    State(b"\x01")
  } else {
    State(b"\x00")
  }
}

///|
/// Derive a raw-mode state from this captured terminal state.
#cfg(target="wasm")
pub fn State::make_raw(self : Self) -> State {
  ignore(self)
  State(b"\x01")
}

///|
/// Apply a terminal state and return the previous state.
///
/// Talks to the sidecar, so on wasm this is async and may raise any error
/// the pipe write can raise.
#cfg(target="wasm")
pub async fn Tty::set_state(self : Self, state : State) -> State {
  let sidecar = self.sidecar_or_raise("Tty::set_state")
  let old_state = self.get_state()
  sidecar.set_raw(state.0 == b"\x01")
  old_state
}

///|
/// Enter raw mode and return the previous terminal state.
#cfg(target="wasm")
pub async fn Tty::enter_raw_mode(self : Self) -> State {
  self.set_state(State(b"\x01"))
}

///|
/// Restore a terminal state captured before or during raw mode.
#cfg(target="wasm")
pub async fn Tty::leave_raw_mode(self : Self, state : State) -> Unit {
  ignore(self.set_state(state))
}

///|
#cfg(target="wasm")
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int32,
) -> Event {
  for ;; {
    if self.resize_pending {
      self.resize_pending = false
      return Resize(self.window_size())
    }
    try read_decoded_input_event(self.reader, esc_timeout_ms) catch {
      @sidecar.Resized => self.resize_pending = true
      error => raise error
    } noraise {
      event => return event
    }
  }
}

///|
#cfg(target="wasm")
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int32,
) -> @input.Event {
  for ;; {
    try self.reader.read_event(esc_timeout_ms~) catch {
      @sidecar.Resized => self.resize_pending = true
      error => raise error
    } noraise {
      event => return event
    }
  }
}
