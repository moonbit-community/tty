///|
/// A mutual-exclusion lock.
///
/// `Lock` wraps a binary semaphore: at most one task can hold it at a time.
/// Other tasks calling `acquire` block until the holder calls `release`, and
/// waiters are served first-come-first-serve. Prefer `with_lock`, which pairs
/// the acquire/release for you and releases even when the action fails.
struct Lock(@async/semaphore.Semaphore)

///|
/// Create a new, unlocked `Lock`.
pub fn Lock::new() -> Lock {
  Lock(Semaphore(1))
}

///|
/// Acquire the lock, blocking until it is available.
///
/// As a blocking point, `acquire` may be cancelled, in which case the lock is
/// not held and the cancellation is raised. Every successful `acquire` must be
/// matched by exactly one `release`.
pub async fn Lock::acquire(self : Lock) -> Unit {
  self.0.acquire()
}

///|
/// Try to acquire the lock without blocking.
///
/// Returns `true` and takes the lock if it was free, otherwise returns `false`
/// immediately. A successful acquisition must be matched by one `release`.
pub fn Lock::try_acquire(self : Lock) -> Bool {
  self.0.try_acquire()
}

///|
/// Release the lock, waking the next waiter if any.
pub fn Lock::release(self : Lock) -> Unit {
  self.0.release()
}

///|
/// Run `action` while holding the lock, returning its result.
///
/// The lock is released whether `action` returns normally or fails. If
/// `acquire` is cancelled before the lock is taken, `action` does not run.
pub async fn[X] Lock::with_lock(self : Lock, action : async () -> X) -> X {
  self.acquire()
  defer self.release()
  action()
}
