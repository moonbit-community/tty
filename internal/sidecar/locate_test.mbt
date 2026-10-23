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

///|
/// A sidecar that fails after it was started is reaped by `spawn`, which
/// also removes its temporary directory. `open` then reports the sidecar's
/// failure, not that the directory was already gone.
async test "a failed open reports the sidecar's failure" {
  let sidecar = @sidecar.open() catch {
    @os_error.OSError(_, ..) as err if err.is_ENOENT() =>
      fail("open reported a cleanup error: \{err}")
    _ => return
  }
  sidecar.close()
  sidecar.wait()
}
