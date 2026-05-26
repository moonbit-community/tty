///|
async fn with_pipe_tty(input_bytes : Bytes, f : async (Tty) -> Unit) -> String {
  @async.with_task_group() <| group => {
    let (input, input_writer) = @async/pipe.pipe()
    let (output_reader, output) = @async/pipe.pipe()
    defer output_reader.close()
    if input_bytes.length() == 0 {
      input_writer.close()
    } else {
      group.spawn_bg() <| () => {
        defer input_writer.close()
        input_writer.write(input_bytes)
      }
    }
    {
      let tty = Tty::new(input, output)
      defer tty.close()
      f(tty)
    }
    output_reader.read_all().text()
  }
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
async test "pipe tty terminal commands write sequences" {
  let output = with_pipe_tty(b"", tty => {
    tty.enter_alt_screen()
    tty.enable_bracketed_paste()
    tty.hide_cursor()
    tty.set_cursor_position(3, 4)
    tty.cursor_up(2)
    tty.cursor_forward(3)
    tty.erase_line_all()
    tty.set_top_bottom_margins(1, 5)
    tty.reverse_index()
    tty.reset_top_bottom_margins()
    tty.set_foreground(@color.Basic(@color.Red))
    tty.reset_foreground()
    tty.set_background(@color.Indexed(42))
    tty.reset_background()
    tty.bold()
    tty.reset_bold()
    tty.italic()
    tty.reset_italic()
    tty.underline()
    tty.reset_underline()
    tty.reverse()
    tty.reset_reverse()
    tty.reset_style()
    tty.show_cursor()
    tty.disable_bracketed_paste()
    tty.leave_alt_screen()
  })
  inspect(
    output,
    content="\u{1B}[?1049h\u{1B}[?2004h\u{1B}[?25l\u{1B}[3;4H\u{1B}[2A\u{1B}[3C\u{1B}[2K\u{1B}[1;5r\u{1B}M\u{1B}[r\u{1B}[31m\u{1B}[39m\u{1B}[48;5;42m\u{1B}[49m\u{1B}[1m\u{1B}[22m\u{1B}[3m\u{1B}[23m\u{1B}[4m\u{1B}[24m\u{1B}[7m\u{1B}[27m\u{1B}[0m\u{1B}[?25h\u{1B}[?2004l\u{1B}[?1049l",
  )
}

///|
async test "pipe tty mouse mode commands write sequences" {
  let output = with_pipe_tty(b"", tty => {
    tty.enable_mouse(Click)
    tty.disable_mouse()
    tty.enable_mouse(Drag)
    tty.disable_mouse()
    tty.enable_mouse(Motion)
    tty.disable_mouse()
  })
  inspect(
    output,
    content="\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006h\u{1B}[?1000h\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006h\u{1B}[?1002h\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006h\u{1B}[?1003h\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006l",
  )
}

///|
async test "pipe tty with mouse restores on success" {
  let output = with_pipe_tty(b"", tty => {
    tty.with_mouse(Drag, () => tty.write("body"))
  })
  inspect(
    output,
    content="\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006h\u{1B}[?1002hbody\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1006l",
  )
}

///|
async test "tty query cursor position coordinates input and output" {
  let output = with_pipe_tty(b"a\x1b[7;9R", tty => {
    match tty.query_cursor_position() {
      Some(pos) => {
        @debug.assert_eq(pos.row, 7)
        @debug.assert_eq(pos.col, 9)
      }
      None => fail("expected cursor position")
    }
    match tty.read_event() {
      Input(event) =>
        @debug.assert_eq(
          event,
          @public_input.Key(
            @public_input.KeyEvent::new(@public_input.Char('a'), text="a"),
          ),
        )
      Resize(_) => fail("expected pending input")
    }
  })
  inspect(output, content="\u{1B}[6n")
}

///|
async test "pipe tty with alt screen restores on success" {
  let output = with_pipe_tty(b"", tty => {
    tty.with_alt_screen(() => tty.write("body"))
  })
  inspect(output, content="\u{1B}[?1049hbody\u{1B}[?1049l")
}

///|
async test "tty query kitty keyboard support returns true for flags reply" {
  let output = with_pipe_tty(b"\x1b[?1u", tty => {
    @debug.assert_eq(tty.query_kitty_keyboard_support(), true)
  })
  inspect(output, content="\u{1B}[?u\u{1B}[c")
}

///|
async test "tty query kitty keyboard support returns false for da reply" {
  let output = with_pipe_tty(b"\x1b[?1;2c", tty => {
    @debug.assert_eq(tty.query_kitty_keyboard_support(), false)
  })
  inspect(output, content="\u{1B}[?u\u{1B}[c")
}

///|
async test "tty query kitty keyboard support preserves interleaved input" {
  let output = with_pipe_tty(b"a\x1b[?1u", tty => {
    @debug.assert_eq(tty.query_kitty_keyboard_support(), true)
    match tty.read_event() {
      Input(event) =>
        @debug.assert_eq(
          event,
          @public_input.Key(
            @public_input.KeyEvent::new(@public_input.Char('a'), text="a"),
          ),
        )
      Resize(_) => fail("expected pending input")
    }
  })
  inspect(output, content="\u{1B}[?u\u{1B}[c")
}

///|
async test "tty window size rejects non tty output" {
  ignore(
    with_pipe_tty(b"", tty => assert_true((try? tty.window_size()) is Err(_))),
  )
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
async test "tty state operations reject non tty pipe" {
  ignore(
    with_pipe_tty(b"", tty => {
      let state = State::new()
      assert_true((try? tty.get_state()) is Err(_))
      assert_true((try? tty.set_state(state)) is Err(_))
      assert_true((try? tty.enter_raw_mode()) is Err(_))
      assert_true((try? tty.leave_raw_mode(state)) is Err(_))
      assert_true((try? tty.with_raw_mode(() => ())) is Err(_))
    }),
  )
}
