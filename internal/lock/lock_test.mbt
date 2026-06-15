///|
/// A held lock keeps concurrent critical sections from overlapping, even when
/// the holder suspends.
async test "with_lock serializes concurrent critical sections" {
  let lock = @lock.Lock::new()
  let mut in_critical = false
  let mut overlaps = 0
  let order = []
  @async.with_task_group(group => {
    for id in 0..<5 {
      group.spawn_bg(() => {
        lock.with_lock(() => {
          if in_critical {
            overlaps += 1
          }
          in_critical = true
          // Suspend while holding the lock; a missing lock would let another task
          // enter here and trip the `overlaps` counter.
          @async.sleep(1)
          order.push(id)
          in_critical = false
        })
      })
    }
  })
  assert_eq(overlaps, 0)
  assert_eq(order.length(), 5)
}

///|
/// `with_lock` releases the lock even when the action fails.
async test "with_lock releases on failure" {
  let lock = @lock.Lock::new()
  let failed = try {
    lock.with_lock(() => fail("boom"))
    false
  } catch {
    _ => true
  }
  assert_eq(failed, true)
  // The lock must be free again, so a follow-up acquire succeeds immediately.
  assert_eq(lock.try_acquire(), true)
  lock.release()
}
