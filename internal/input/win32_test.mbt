///|
async test "win32 keys preserve modifiers keypad AltGr and repeat count" {
  with_input(
    b"\x1b[65;30;65;1;16;1_\x1b[13;28;13;1;256;1_\x1b[69;18;8364;1;9;1_\x1b[65;30;97;1;0;3_",
    events => {
      @debug.assert_eq(
        events.read_event(),
        input_key(
          @public_input.KeyEvent::new(
            Char('A'),
            text="A",
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(
          @public_input.KeyEvent::new(
            KeypadEnter,
            state=@public_input.KeyEventState::new(keypad=true),
          ),
        ),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char('€'), text="€")),
      )
      for _ in 0..<3 {
        @debug.assert_eq(
          events.read_event(),
          input_key(
            @public_input.KeyEvent::new(Char('a'), text="a", kind=Repeat),
          ),
        )
      }
    },
  )
}

///|
async test "win32 omitted fields ctrl space ctrl bracket and key up" {
  with_input(
    b"\x1b[32;;;1;8_\x1b[219;;27;1;8_\x1b[65;30;97;0_\x1b[65;30;97;1_",
    events => {
      let ctrl = @public_input.KeyModifiers::new(ctrl=true)
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char(' '), modifiers=ctrl)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char('['), modifiers=ctrl)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
      )
    },
  )
}

///|
async test "win32 surrogate pair survives intervening release" {
  with_input(b"\x1b[231;0;55357;1_\x1b[231;0;55357;0_\x1b[231;0;56832;1_", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('😀'), text="😀")),
    )
  })
}

///|
async test "win32 malformed fields stay unknown" {
  for
    bytes in [
      b"\x1b[65;0;65536;1_", b"\x1b[65;0;97;2_", b"\x1b[65;0;97;1;0;1;2_", b"\x1b[65:1;0;97;1_",
      b"\x1b[4294967361;0;97;1_",
    ] {
    with_input(bytes, events => {
      @debug.assert_eq(events.read_event(), input_unknown(bytes))
    })
  }
}

///|
fn wrap_win32_text(text : String) -> Bytes {
  let buffer = Buffer()
  for char in text {
    buffer.write_utf8("\u{1b}[0;0;\{char.to_int()};1;0;1_")
  }
  buffer.to_bytes()
}

///|
async test "win32 character envelopes preserve VT framing" {
  with_input(
    wrap_win32_text(
      "\u{1b}[200~hello\u{1b}[201~\u{1b}[I\u{1b}[<0;20;4M\u{1b}[7;9R\u{1b}]10;rgb:ff/00/00\u{7}",
    ),
    events => {
      @debug.assert_eq(events.read_event(), input_paste("hello"))
      @debug.assert_eq(events.read_event(), input_focus_in())
      @debug.assert_eq(
        events.read_event(),
        Input(Mouse(@public_input.MouseEvent::new(Press(Left), 4, 20))),
      )
      @debug.assert_eq(events.read_event(), CursorPosition(row=7, col=9))
      @debug.assert_eq(
        events.read_event(),
        DynamicColor(code=10, red=65535, green=0, blue=0),
      )
    },
  )
}

///|
async test "win32 envelope surrogate pairs and synthetic releases" {
  with_input(
    b"\x1b[0;0;55357;1_\x1b[0;0;56832;1_\x1b[0;0;97;0_\x1b[0;0;98;1_",
    events => {
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char('😀'), text="😀")),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char('b'), text="b")),
      )
    },
  )
}

///|
async test "win32 fragmented key frame" {
  with_delayed_input(b"\x1b[65;30;", b"97;1_", 5, events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "win32 cancellation preserves a partial key frame" {
  with_delayed_input(b"\x1b[65;30;", b"97;1_", 30, events => {
    assert_true(
      @async.with_timeout_opt(5, () => events.read_event(esc_timeout_ms=100))
      is None,
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "win32 cancellation preserves partial wrapped paste" {
  with_delayed_input(
    wrap_win32_text("\u{1b}[200~hel"),
    wrap_win32_text("lo\u{1b}[201~"),
    30,
    events => {
      assert_true(
        @async.with_timeout_opt(5, () => events.read_event(esc_timeout_ms=100))
        is None,
      )
      @debug.assert_eq(events.read_event(), input_paste("hello"))
    },
  )
}

///|
async test "win32 mode responses remain internal" {
  with_input(b"\x1b[?9001;2$y", events => {
    @debug.assert_eq(events.read_event(), Win32InputMode(2))
  })
}

///|
async test "win32 bracketed paste unwraps key records without interpreting keys" {
  let bytes : Bytes = [
    ..wrap_win32_text("\u{1b}[200~"),
    ..b"\x1b[65;30;65;1;16_\x1b[65;30;65;0;16_\x1b[13;28;13;1_",
    ..wrap_win32_text("\u{1b}[201~"),
  ]
  with_input(bytes, events => {
    @debug.assert_eq(events.read_event(), input_paste("A\r"))
  })
}

///|
async test "win32 fragmented wrapped VT sequence" {
  with_delayed_input(b"\x1b[0;0;27;1_\x1b[0;0;", b"91;1_\x1b[0;0;73;1_", 5, events => {
    @debug.assert_eq(events.read_event(), input_focus_in())
  })
}

///|
async test "win32 parser accepts DWORD control flags" {
  with_input(b"\x1b[65;30;97;1;2147483648_", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "win32 preview does not extend the escape timeout" {
  with_delayed_input(b"\x1b[65;30;", b"97;1_", 35, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=20),
      input_unknown(b"\x1b[65;30;"),
    )
    for char in "97;1_" {
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Char(char), text=[char])),
      )
    }
  })
}

///|
async test "win32 pasted surrogate pair ignores intervening release" {
  let bytes : Bytes = [
    ..wrap_win32_text("\u{1b}[200~"),
    ..b"\x1b[231;0;55357;1_\x1b[231;0;55357;0_\x1b[231;0;56832;1_\x1b[231;0;56832;0_",
    ..wrap_win32_text("\u{1b}[201~"),
  ]
  with_input(bytes, events => {
    @debug.assert_eq(events.read_event(), input_paste("😀"))
  })
}
