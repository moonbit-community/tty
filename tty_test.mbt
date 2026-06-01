///|
async fn with_pipe_tty_output(f : async (@tty.Tty) -> Unit) -> String {
  let (input, input_writer) = @async/pipe.pipe()
  let (output_reader, output) = @async/pipe.pipe()
  defer output_reader.close()
  input_writer.close()
  {
    let tty = @tty.Tty::new(input, output)
    defer tty.close()
    f(tty)
  }
  output_reader.read_all().text()
}

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
async test "pipe tty with alt screen restores on success" {
  let output = with_pipe_tty_output(tty => {
    tty.with_alt_screen(() => tty.write("body"))
  })
  inspect(output, content="\u{1B}[?1049hbody\u{1B}[?1049l")
}

///|
async test "pipe tty with top bottom margins restores on success" {
  let output = with_pipe_tty_output(tty => {
    let value = tty.with_top_bottom_margins(2, 7, () => {
      tty.write("body")
      42
    })
    assert_true(value == 42)
  })
  inspect(output, content="\u{1B}[2;7rbody\u{1B}[r")
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
