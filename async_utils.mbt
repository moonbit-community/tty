///|
const CleanupTimeoutMs : Int = 50

///|
async fn[T] with_deferred(cleanup : async () -> Unit, f : async () -> T) -> T {
  try f() catch {
    error =>
      try
        @async.protect_from_cancel() <| () => {
          @async.with_timeout(CleanupTimeoutMs, cleanup)
        }
      catch {
        // Cleanup is best-effort once the body has failed; preserve the body
        // failure so callers do not observe cleanup timeout or cleanup I/O
        // errors instead.
        _ => raise error
      } noraise {
        _ => raise error
      }
  } noraise {
    value => {
      cleanup()
      value
    }
  }
}
