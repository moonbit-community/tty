///|
priv suberror CleanupError

///|
priv suberror OriginalError

///|
async test "with_deferred preserves original error on cleanup failure" {
  try with_deferred(() => raise CleanupError, () => raise OriginalError) catch {
    OriginalError => ()
    error => raise error
  } noraise {
    (_ : Unit) => fail("expected OriginalError")
  }
}

///|
async test "with_deferred preserves original error on cleanup timeout" {
  let mut cleanup_finished = false
  try
    with_deferred(
      () => {
        @async.sleep(CleanupTimeoutMs * 2)
        cleanup_finished = true
      },
      () => raise OriginalError,
    )
  catch {
    OriginalError => assert_false(cleanup_finished)
    error => raise error
  } noraise {
    (_ : Unit) => fail("expected OriginalError")
  }
}
