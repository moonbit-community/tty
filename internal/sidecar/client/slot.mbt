///|
/// Map a host stdio handle to a sidecar terminal slot. Handles other than
/// the process stdio cannot be named across the process boundary.
pub fn stdio_slot(fd : @async/types.Fd) -> Int? raise {
  if fd == @async/stdio.stdin.fd() {
    Some(0)
  } else if fd == @async/stdio.stdout.fd() {
    Some(1)
  } else if fd == @async/stdio.stderr.fd() {
    Some(2)
  } else {
    None
  }
}

///|
/// Slot used for handles that are not the process stdio: the sidecar
/// rejects it with `EINVAL`, mirroring how native terminal calls fail on
/// non-terminal fds.
const INVALID_SLOT : Int = 255

///|
pub fn stdio_slot_or_invalid(fd : @async/types.Fd) -> Int raise {
  stdio_slot(fd).unwrap_or(INVALID_SLOT)
}
