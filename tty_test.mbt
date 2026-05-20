///|
async test "Tty::open() when controlling tty is available" {
  try @tty.Input::open() catch {
    _ => ()
  } noraise {
    ti => ti.close()
  }
  try @tty.Output::open() catch {
    _ => ()
  } noraise {
    to =>
      try to.window_size() catch {
        _ => {
          to.close()
          fail("expected /dev/tty window size")
        }
      } noraise {
        size => {
          to.close()
          assert_true(size.rows > 0)
          assert_true(size.cols > 0)
        }
      }
  }
}

///|
test "stdout window size when stdout is a tty" {
  if @tty.isatty(@tty.stdout.fd()) {
    try @tty.stdout.window_size() catch {
      _ => fail("expected stdout window size")
    } noraise {
      size => {
        assert_true(size.rows > 0)
        assert_true(size.cols > 0)
      }
    }
  }
}
