///|
async fn with_pipe_tty(
  input_bytes : Bytes,
  f : async (@tty.Tty) -> Unit,
) -> String {
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
      let tty = @tty.Tty::new(input, output)
      defer tty.close()
      f(tty)
    }
    output_reader.read_all().text()
  }
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
    tty.erase_display()
    tty.erase_scrollback()
    tty.set_top_bottom_margins(1, 5)
    tty.reverse_index()
    tty.reset_top_bottom_margins()
    tty.set_foreground(Basic(Red))
    tty.reset_foreground()
    tty.set_background(Indexed(42))
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
    content="\u{1B}[?1049h\u{1B}[?2004h\u{1B}[?25l\u{1B}[3;4H\u{1B}[2A\u{1B}[3C\u{1B}[2K\u{1B}[2J\u{1B}[3J\u{1B}[1;5r\u{1B}M\u{1B}[r\u{1B}[31m\u{1B}[39m\u{1B}[48;5;42m\u{1B}[49m\u{1B}[1m\u{1B}[22m\u{1B}[3m\u{1B}[23m\u{1B}[4m\u{1B}[24m\u{1B}[7m\u{1B}[27m\u{1B}[0m\u{1B}[?25h\u{1B}[?2004l\u{1B}[?1049l",
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
async test "pipe tty focus tracking commands write sequences" {
  let output = with_pipe_tty(b"", tty => {
    tty.enable_focus_tracking()
    tty.disable_focus_tracking()
  })
  inspect(output, content="\u{1B}[?1004h\u{1B}[?1004l")
}

///|
async test "pipe tty auto wrap commands write sequences" {
  let output = with_pipe_tty(b"", tty => {
    tty.enable_auto_wrap()
    tty.disable_auto_wrap()
  })
  inspect(output, content="\u{1B}[?7h\u{1B}[?7l")
}

///|
async test "pipe tty with focus tracking restores on success" {
  let output = with_pipe_tty(b"", tty => {
    tty.with_focus_tracking(() => tty.write("body"))
  })
  inspect(output, content="\u{1B}[?1004hbody\u{1B}[?1004l")
}

///|
test "keyboard enhancement flags encode bits" {
  let flags = @tty.KeyboardEnhancementFlags::new(
    disambiguate_escape_codes=true,
    report_event_types=true,
    report_alternate_keys=true,
    report_all_keys_as_escape_codes=true,
    report_associated_text=true,
  )
  @debug.assert_eq(flags.bits(), 31)
  @debug.assert_eq(flags.disambiguate_escape_codes(), true)
  @debug.assert_eq(flags.report_event_types(), true)
  @debug.assert_eq(flags.report_alternate_keys(), true)
  @debug.assert_eq(flags.report_all_keys_as_escape_codes(), true)
  @debug.assert_eq(flags.report_associated_text(), true)
  @debug.assert_eq(@tty.KeyboardEnhancementFlags::disambiguate().bits(), 1)
  @debug.assert_eq(@tty.KeyboardEnhancementFlags::full().bits(), 31)
}

///|
async test "pipe tty keyboard enhancement commands write sequences" {
  let output = with_pipe_tty(b"", tty => {
    tty.push_keyboard_enhancement_flags(
      @tty.KeyboardEnhancementFlags::new(
        disambiguate_escape_codes=true,
        report_event_types=true,
      ),
    )
    tty.pop_keyboard_enhancement_flags()
  })
  inspect(output, content="\u{1B}[>3u\u{1B}[<1u")
}

///|
async test "pipe tty with keyboard enhancements restores on success" {
  let output = with_pipe_tty(b"", tty => {
    tty.with_keyboard_enhancements(
      @tty.KeyboardEnhancementFlags::disambiguate(),
      () => tty.write("body"),
    )
  })
  inspect(output, content="\u{1B}[>1ubody\u{1B}[<1u")
}

///|
async test "pipe tty with kitty keyboard uses full flags" {
  let output = with_pipe_tty(b"", tty => {
    tty.with_kitty_keyboard(() => tty.write("body"))
  })
  inspect(output, content="\u{1B}[>31ubody\u{1B}[<1u")
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
          Key(@public_input.KeyEvent::new(Char('a'), text="a")),
        )
      Resize(_) => fail("expected pending input")
    }
  })
  inspect(output, content="\u{1B}[6n")
}

///|
async test "tty query cursor position preserves interleaved focus input" {
  let output = with_pipe_tty(b"\x1b[I\x1b[7;9R", tty => {
    match tty.query_cursor_position() {
      Some(pos) => {
        @debug.assert_eq(pos.row, 7)
        @debug.assert_eq(pos.col, 9)
      }
      None => fail("expected cursor position")
    }
    match tty.read_event() {
      Input(event) => @debug.assert_eq(event, FocusIn)
      Resize(_) => fail("expected pending input")
    }
  })
  inspect(output, content="\u{1B}[6n")
}

///|
async test "tty query dynamic colors coordinates input and output" {
  let output = with_pipe_tty(
    b"a\x1b]10;rgb:ff/00/80\x07\x1b]11;rgb:0000/ffff/0000\x1b\\\x1b]12;rgb:0/0/f\x07",
    tty => {
      match tty.query_default_foreground_color() {
        Some(color) => {
          @debug.assert_eq(color.red, 65535)
          @debug.assert_eq(color.green, 0)
          @debug.assert_eq(color.blue, 32896)
        }
        None => fail("expected foreground color")
      }
      match tty.query_default_background_color() {
        Some(color) => {
          @debug.assert_eq(color.red, 0)
          @debug.assert_eq(color.green, 65535)
          @debug.assert_eq(color.blue, 0)
        }
        None => fail("expected background color")
      }
      match tty.query_cursor_color() {
        Some(color) => {
          @debug.assert_eq(color.red, 0)
          @debug.assert_eq(color.green, 0)
          @debug.assert_eq(color.blue, 65535)
        }
        None => fail("expected cursor color")
      }
      match tty.read_event() {
        Input(event) =>
          @debug.assert_eq(
            event,
            Key(@public_input.KeyEvent::new(Char('a'), text="a")),
          )
        Resize(_) => fail("expected pending input")
      }
    },
  )
  inspect(
    output,
    content="\u{1B}]10;?\u{1B}\\\u{1B}]11;?\u{1B}\\\u{1B}]12;?\u{1B}\\",
  )
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
          Key(@public_input.KeyEvent::new(Char('a'), text="a")),
        )
      Resize(_) => fail("expected pending input")
    }
  })
  inspect(output, content="\u{1B}[?u\u{1B}[c")
}

///|
async test "tty window size rejects non tty output" {
  ignore(
    with_pipe_tty(b"", tty => {
      try tty.window_size() catch {
        _ => ()
      } noraise {
        _ => fail("expected window_size to reject non tty output")
      }
    }),
  )
}

///|
async test "tty raw mode operations reject non tty pipe" {
  ignore(
    with_pipe_tty(b"", tty => {
      try tty.get_state() catch {
        _ => ()
      } noraise {
        _ => fail("expected get_state to reject non tty pipe")
      }
      try tty.enter_raw_mode() catch {
        _ => ()
      } noraise {
        _ => fail("expected enter_raw_mode to reject non tty pipe")
      }
      try tty.with_raw_mode(() => ()) catch {
        _ => ()
      } noraise {
        _ => fail("expected with_raw_mode to reject non tty pipe")
      }
    }),
  )
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
  let output = with_pipe_tty(b"", tty => {
    tty.with_alt_screen(() => tty.write("body"))
  })
  inspect(output, content="\u{1B}[?1049hbody\u{1B}[?1049l")
}

///|
async test "pipe tty with top bottom margins restores on success" {
  let output = with_pipe_tty(b"", tty => {
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
