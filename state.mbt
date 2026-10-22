///|
/// The sidecar that holds this handle's terminal, or `OSError(ENOTSUP)` for
/// stream handles, which have no terminal state of their own.
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
/// Enter raw mode: no echo, no line buffering, no signal keys, VT input.
/// Entering it twice is a no-op.
pub async fn Tty::enter_raw_mode(self : Self) -> Unit {
  self.sidecar_or_raise("Tty::enter_raw_mode").set_raw(true)
}

///|
/// Leave raw mode and restore the terminal as it was before entering it.
/// Leaving twice is a no-op.
pub async fn Tty::leave_raw_mode(self : Self) -> Unit {
  self.sidecar_or_raise("Tty::leave_raw_mode").set_raw(false)
}

///|
/// Run an async callback with raw mode enabled.
///
/// The terminal is restored on success, error, or cancellation, by the
/// outermost of nested scopes.
pub async fn[T] Tty::with_raw_mode(self : Self, f : async () -> T) -> T {
  self.enter_raw_mode()
  self.raw_depth += 1
  defer self.leave_raw_scope()
  f()
}

///|
/// Leave raw mode when the last `with_raw_mode` scope ends. Restoring the
/// terminal must happen even while the task is being cancelled.
async fn Tty::leave_raw_scope(self : Self) -> Unit {
  self.raw_depth -= 1
  if self.raw_depth == 0 {
    @async.protect_from_cancel(() => self.leave_raw_mode())
  }
}
