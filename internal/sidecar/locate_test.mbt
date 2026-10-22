///|
/// Without a usable terminal the sidecar reports an error and exits at
/// once, so `open` reaps a process that is already gone; with a terminal,
/// `close` ends it right away. Either way reaping must not fail or trap,
/// which on Windows used to depend on how fast the process went away.
async test "open and reap the sidecar repeatedly" {
  for _ in 0..<20 {
    let sidecar = @sidecar.open() catch { _ => continue }
    sidecar.close()
    sidecar.wait()
  }
}
