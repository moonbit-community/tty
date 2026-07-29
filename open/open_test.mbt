///|
async test "open() when controlling tty is available" {
  try @open.open() catch {
    _ => ()
  } noraise {
    tty =>
      try tty.window_size() catch {
        _ => {
          tty.close()
          fail("expected /dev/tty window size")
        }
      } noraise {
        size => {
          tty.close()
          assert_true(size.rows > 0)
          assert_true(size.cols > 0)
        }
      }
  }
}
