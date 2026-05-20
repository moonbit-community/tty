///|
async test "file input wrapper delegates reads" {
  let path = "_build/tty_file_input_wrapper_test"
  @async/fs.write_file(path, b"az", create_mode=CreateOrTruncate)
  {
    let input = Input::File(@async/fs.open(path, mode=ReadOnly))
    defer input.close()
    assert_true(input.fd() >= 0)
    let buf = FixedArray::make(2, b'\x00')
    inspect(input.read(buf), content="2")
    assert_true(buf[0] == b'a')
    assert_true(buf[1] == b'z')
  }
  {
    let input = Input::File(@async/fs.open(path, mode=ReadOnly))
    defer input.close()
    guard input.read_some() is Some(bytes) else {
      fail("expected file input to read bytes")
    }
    assert_true(bytes == b"az")
  }
  {
    let input = Input::File(@async/fs.open(path, mode=ReadOnly))
    defer input.close()
    assert_true(input.read_byte() == b'a')
  }
  @async/fs.remove(path)
}

///|
test "style color sequences encode semantic colors" {
  @debug.assert_eq(foreground_sequence(@color.Default), b"\x1b[39m")
  @debug.assert_eq(foreground_sequence(@color.Basic(@color.Black)), b"\x1b[30m")
  @debug.assert_eq(foreground_sequence(@color.Basic(@color.Red)), b"\x1b[31m")
  @debug.assert_eq(foreground_sequence(@color.Basic(@color.White)), b"\x1b[37m")
  @debug.assert_eq(
    foreground_sequence(@color.Basic(@color.BrightBlack)),
    b"\x1b[90m",
  )
  @debug.assert_eq(
    foreground_sequence(@color.Basic(@color.BrightRed)),
    b"\x1b[91m",
  )
  @debug.assert_eq(
    foreground_sequence(@color.Basic(@color.BrightWhite)),
    b"\x1b[97m",
  )
  @debug.assert_eq(background_sequence(@color.Default), b"\x1b[49m")
  @debug.assert_eq(background_sequence(@color.Basic(@color.Black)), b"\x1b[40m")
  @debug.assert_eq(background_sequence(@color.Basic(@color.Red)), b"\x1b[41m")
  @debug.assert_eq(background_sequence(@color.Basic(@color.White)), b"\x1b[47m")
  @debug.assert_eq(
    background_sequence(@color.Basic(@color.BrightBlack)),
    b"\x1b[100m",
  )
  @debug.assert_eq(
    background_sequence(@color.Basic(@color.BrightRed)),
    b"\x1b[101m",
  )
  @debug.assert_eq(
    background_sequence(@color.Basic(@color.BrightWhite)),
    b"\x1b[107m",
  )
  @debug.assert_eq(foreground_sequence(@color.Indexed(-1)), b"\x1b[38;5;0m")
  @debug.assert_eq(foreground_sequence(@color.Indexed(42)), b"\x1b[38;5;42m")
  @debug.assert_eq(foreground_sequence(@color.Indexed(999)), b"\x1b[38;5;255m")
  @debug.assert_eq(background_sequence(@color.Indexed(-1)), b"\x1b[48;5;0m")
  @debug.assert_eq(background_sequence(@color.Indexed(42)), b"\x1b[48;5;42m")
  @debug.assert_eq(background_sequence(@color.Indexed(999)), b"\x1b[48;5;255m")
  @debug.assert_eq(
    foreground_sequence(@color.Rgb(-1, 127, 999)),
    b"\x1b[38;2;0;127;255m",
  )
  @debug.assert_eq(
    background_sequence(@color.Rgb(-1, 127, 999)),
    b"\x1b[48;2;0;127;255m",
  )
}

///|
async test "file output wrapper delegates writes" {
  let path = "_build/tty_file_output_wrapper_test"
  {
    let output = Output::File(
      @async/fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate),
    )
    defer output.close()
    assert_true(output.fd() >= 0)
    output.write("ab")
    output.write_string("cd")
  }
  inspect(@async/fs.read_file(path).text(), content="abcd")
  @async/fs.remove(path)
}

///|
async test "file tty terminal commands write sequences" {
  let input_path = "_build/tty_file_commands_input_test"
  let output_path = "_build/tty_file_output_commands_test"
  @async/fs.write_file(input_path, b"", create_mode=CreateOrTruncate)
  {
    let input = @async/fs.open(input_path, mode=ReadOnly)
    let output = @async/fs.open(
      output_path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let tty = Tty::new(input, output)
    defer tty.close()
    tty.enter_alt_screen()
    tty.hide_cursor()
    tty.set_foreground(@color.Basic(@color.Red))
    tty.reset_foreground()
    tty.set_background(@color.Indexed(42))
    tty.reset_background()
    tty.reset_style()
    tty.show_cursor()
    tty.leave_alt_screen()
  }
  inspect(
    @async/fs.read_file(output_path).text(),
    content="\u{1B}[?1049h\u{1B}[?25l\u{1B}[31m\u{1B}[39m\u{1B}[48;5;42m\u{1B}[49m\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l",
  )
  @async/fs.remove(input_path)
  @async/fs.remove(output_path)
}

///|
async test "tty query cursor position coordinates input and output" {
  let input_path = "_build/tty_query_cursor_position_input_test"
  let output_path = "_build/tty_query_cursor_position_output_test"
  @async/fs.write_file(input_path, b"\x1b[7;9Ra", create_mode=CreateOrTruncate)
  {
    let input = @async/fs.open(input_path, mode=ReadOnly)
    let output = @async/fs.open(
      output_path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let tty = Tty::new(input, output)
    defer tty.close()
    match tty.query_cursor_position() {
      Some(pos) => {
        @debug.assert_eq(pos.row, 7)
        @debug.assert_eq(pos.col, 9)
      }
      None => fail("expected cursor position")
    }
    @debug.assert_eq(
      tty.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  }
  inspect(@async/fs.read_file(output_path).text(), content="\u{1B}[6n")
  @async/fs.remove(input_path)
  @async/fs.remove(output_path)
}

///|
async test "file tty with alt screen restores on success" {
  let input_path = "_build/tty_file_alt_screen_input_test"
  let output_path = "_build/tty_file_output_with_alt_screen_test"
  @async/fs.write_file(input_path, b"", create_mode=CreateOrTruncate)
  {
    let input = @async/fs.open(input_path, mode=ReadOnly)
    let output = @async/fs.open(
      output_path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let tty = Tty::new(input, output)
    defer tty.close()
    tty.with_alt_screen(() => tty.write("body"))
  }
  inspect(
    @async/fs.read_file(output_path).text(),
    content="\u{1B}[?1049hbody\u{1B}[?1049l",
  )
  @async/fs.remove(input_path)
  @async/fs.remove(output_path)
}

///|
async test "tty window size rejects non tty output" {
  let input_path = "_build/tty_window_size_input_test"
  let output_path = "_build/tty_window_size_non_tty_test"
  @async/fs.write_file(input_path, b"", create_mode=CreateOrTruncate)
  {
    let input = @async/fs.open(input_path, mode=ReadOnly)
    let output = @async/fs.open(
      output_path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let tty = Tty::new(input, output)
    defer tty.close()
    assert_true((try? tty.window_size()) is Err(_))
  }
  @async/fs.remove(input_path)
  @async/fs.remove(output_path)
}

///|
test "stdio wrappers expose descriptors and no op close" {
  assert_true(stdin.fd() >= 0)
  stdin.close()
  assert_true(stdout.fd() >= 0)
  stdout.close()
  assert_true(stderr.fd() >= 0)
  stderr.close()
}

///|
async test "stdio output wrapper delegates empty writes" {
  stdout.write("")
  stdout.write_string("")
}

///|
test "isatty rejects invalid fd" {
  try isatty(-1) catch {
    InvalidFd(fd) => @debug.assert_eq(fd, -1)
  } noraise {
    _ => fail("expected invalid fd error")
  }
}

///|
test "state buffer can be made raw" {
  assert_true(sizeof_state > 0)
  let state = State::new()
  @debug.assert_eq(state.0.length(), sizeof_state)
  let raw = state.make_raw()
  @debug.assert_eq(raw.0.length(), sizeof_state)
}

///|
async test "tty state operations reject non tty file" {
  let input_path = "_build/tty_state_non_tty_input_test"
  let output_path = "_build/tty_state_non_tty_output_test"
  @async/fs.write_file(input_path, b"x", create_mode=CreateOrTruncate)
  {
    let input = @async/fs.open(input_path, mode=ReadOnly)
    let output = @async/fs.open(
      output_path,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let tty = Tty::new(input, output)
    defer tty.close()
    let state = State::new()
    assert_true((try? tty.get_state()) is Err(_))
    assert_true((try? tty.set_state(state)) is Err(_))
    assert_true((try? tty.enter_raw_mode()) is Err(_))
    assert_true((try? tty.leave_raw_mode(state)) is Err(_))
    assert_true((try? tty.with_raw_mode(() => ())) is Err(_))
  }
  @async/fs.remove(input_path)
  @async/fs.remove(output_path)
}
