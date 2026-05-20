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
  {
    let input = Input::File(@async/fs.open(path, mode=ReadOnly))
    defer input.close()
    let events = input.event_reader()
    assert_true(
      events.read_event() ==
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  }
  @async/fs.remove(path)
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
async test "file output terminal commands write sequences" {
  let path = "_build/tty_file_output_commands_test"
  {
    let output = Output::File(
      @async/fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate),
    )
    defer output.close()
    output.enter_alt_screen()
    output.hide_cursor()
    output.set_foreground(@color.Basic(@color.Red))
    output.reset_foreground()
    output.set_background(@color.Indexed(42))
    output.reset_background()
    output.reset_style()
    output.show_cursor()
    output.leave_alt_screen()
  }
  inspect(
    @async/fs.read_file(path).text(),
    content="\u{1B}[?1049h\u{1B}[?25l\u{1B}[31m\u{1B}[39m\u{1B}[48;5;42m\u{1B}[49m\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l",
  )
  @async/fs.remove(path)
}

///|
async test "file output with alt screen restores on success" {
  let path = "_build/tty_file_output_with_alt_screen_test"
  {
    let output = Output::File(
      @async/fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate),
    )
    defer output.close()
    output.with_alt_screen(() => output.write("body"))
  }
  inspect(
    @async/fs.read_file(path).text(),
    content="\u{1B}[?1049hbody\u{1B}[?1049l",
  )
  @async/fs.remove(path)
}

///|
async test "window size rejects non tty output" {
  let path = "_build/tty_window_size_non_tty_test"
  {
    let output = Output::File(
      @async/fs.open(path, mode=WriteOnly, create_mode=CreateOrTruncate),
    )
    defer output.close()
    assert_true((try? output.window_size()) is Err(_))
  }
  @async/fs.remove(path)
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
async test "state operations reject non tty file" {
  let path = "_build/tty_state_non_tty_test"
  @async/fs.write_file(path, b"x", create_mode=CreateOrTruncate)
  let input = Input::File(@async/fs.open(path, mode=ReadOnly))
  defer input.close()
  let state = State::new()
  assert_true((try? input.get_state()) is Err(_))
  assert_true((try? input.set_state(state)) is Err(_))
  assert_true((try? input.enter_raw_mode()) is Err(_))
  assert_true((try? input.leave_raw_mode(state)) is Err(_))
  assert_true((try? input.with_raw_mode(() => ())) is Err(_))
  @async/fs.remove(path)
}
