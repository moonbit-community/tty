///|
async test "Tty::open() when controlling tty is available" {
  try @tty.Tty::open() catch {
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

///|
test "stdout window size when stdout is a tty" {
  if @tty.isatty(@async/stdio.stdout) {
    let tty = @tty.Tty::stdio()
    try tty.window_size() catch {
      _ => fail("expected stdout window size")
    } noraise {
      size => {
        assert_true(size.rows > 0)
        assert_true(size.cols > 0)
      }
    }
  }
}
