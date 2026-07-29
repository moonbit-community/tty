///|
/// Return whether a handle refers to a terminal.
///
/// On wasm only the process stdio handles can be identified across the
/// sidecar boundary; every other handle reports `false`. Sidecar-side
/// failures raise `OSError`.
pub async fn[T : Fd] isatty(fd : T) -> Bool {
  guard stdio_slot(fd.fd()) is Some(which) else { return false }
  match sidecar().call(IsATty(which~)) {
    IsATty(result) => result
    Error(errno~) => raise @os_error.OSError(errno, context="isatty")
    _ => raise @sidecar.ProtocolViolation
  }
}
