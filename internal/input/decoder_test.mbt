///|
async fn with_input(bytes : Bytes, f : async (EventReader) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let (reader, writer) = @io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(bytes)
    }
    f(EventReader::new(reader))
    reader.close()
  }
}

///|
async fn with_delayed_input(
  first : Bytes,
  second : Bytes,
  delay : Int,
  f : async (EventReader) -> Unit,
) -> Unit {
  @async.with_task_group() <| group => {
    let (reader, writer) = @io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(first)
      @async.sleep(delay)
      writer.write(second)
    }
    f(EventReader::new(reader))
    reader.close()
  }
}

///|
fn input_key(key : @public_input.KeyEvent) -> @input.Event {
  Input(Key(key))
}

///|
fn input_unknown(bytes : Bytes) -> @input.Event {
  Input(Unknown(bytes))
}

///|
fn input_paste(text : String) -> @input.Event {
  Input(Paste(text))
}

///|
fn input_focus_in() -> @input.Event {
  Input(FocusIn)
}

///|
fn input_focus_out() -> @input.Event {
  Input(FocusOut)
}

///|
fn input_mouse(mouse : @public_input.MouseEvent) -> @input.Event {
  Input(Mouse(mouse))
}

///|
test "key modifier accessors" {
  let modifiers = @public_input.KeyModifiers::new(
    shift=true,
    alt=true,
    ctrl=true,
    meta=true,
    super_=true,
    hyper=true,
  )
  @debug.assert_eq(modifiers.shift(), true)
  @debug.assert_eq(modifiers.alt(), true)
  @debug.assert_eq(modifiers.ctrl(), true)
  @debug.assert_eq(modifiers.meta(), true)
  @debug.assert_eq(modifiers.super_(), true)
  @debug.assert_eq(modifiers.hyper(), true)
  let none = @public_input.KeyModifiers::new()
  @debug.assert_eq(none.shift(), false)
  @debug.assert_eq(none.alt(), false)
  @debug.assert_eq(none.ctrl(), false)
  @debug.assert_eq(none.meta(), false)
  @debug.assert_eq(none.super_(), false)
  @debug.assert_eq(none.hyper(), false)
}

///|
test "key event state accessors" {
  let state = @public_input.KeyEventState::new(
    keypad=true,
    caps_lock=true,
    num_lock=true,
  )
  @debug.assert_eq(state.keypad(), true)
  @debug.assert_eq(state.caps_lock(), true)
  @debug.assert_eq(state.num_lock(), true)
  let none = @public_input.KeyEventState::new()
  @debug.assert_eq(none.keypad(), false)
  @debug.assert_eq(none.caps_lock(), false)
  @debug.assert_eq(none.num_lock(), false)
}

///|
async test "cursor position response is a stream event" {
  with_input(b"\x1b[12;34R", events => {
    @debug.assert_eq(events.read_event(), CursorPosition(row=12, col=34))
  })
}

///|
async test "kitty keyboard enhancement flags response is a stream event" {
  with_input(b"\x1b[?0u\x1b[?15u", events => {
    @debug.assert_eq(events.read_event(), KeyboardEnhancementFlags(0))
    @debug.assert_eq(events.read_event(), KeyboardEnhancementFlags(15))
  })
}

///|
async test "decode kitty keyboard csi u key event kinds" {
  with_input(b"\x1b[97u\x1b[97;1:2u\x1b[97;1:3u", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), kind=Repeat, text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), kind=Release, text="a")),
    )
  })
}

///|
async test "decode kitty keyboard modifiers alternate keys and associated text" {
  with_input(b"\x1b[105;5u\x1b[61:43;6u\x1b[0;;229u\x1b[0;;101:769u", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('i'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('='),
          modifiers=@public_input.KeyModifiers::new(shift=true, ctrl=true),
          shifted_code=Char('+'),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Text, text="å")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Text, text="e\u{0301}")),
    )
  })
}

///|
async test "invalid kitty keyboard csi u shapes remain unknown input" {
  with_input(
    b"\x1b[u\x1b[;5u\x1b[:43u\x1b[0u\x1b[1u\x1b[97:65;1u\x1b[97:0;1u\x1b[97::0u\x1b[97;0u\x1b[97;:2u\x1b[97;5:u\x1b[97;:u\x1b[97;5:2:9u\x1b[97:65:99:120u\x1b[97;1;65::66u\x1b[97;;10u\x1b[97;1;2;3u",
    events => {
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[;5u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[:43u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[0u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97:65;1u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97:0;1u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97::0u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;0u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;:2u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;5:u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;:u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;5:2:9u"))
      @debug.assert_eq(
        events.read_event(),
        input_unknown(b"\x1b[97:65:99:120u"),
      )
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;1;65::66u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;;10u"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[97;1;2;3u"))
    },
  )
}

///|
async test "decode kitty keyboard functional keys state and extension event kinds" {
  with_input(b"\x1b[57400u\x1b[57444u\x1b[1;5:2A\x1b[3;5:3~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Keypad1,
          state=@public_input.KeyEventState::new(keypad=true),
          text="1",
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Modifier(LeftSuper),
          modifiers=@public_input.KeyModifiers::new(super_=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Up,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
          kind=Repeat,
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Delete,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
          kind=Release,
        ),
      ),
    )
  })
}

///|
async test "primary device attributes response is a stream event" {
  with_input(b"\x1b[?1;2c", events => {
    @debug.assert_eq(
      events.read_event(),
      PrimaryDeviceAttributes(b"\x1b[?1;2c"),
    )
  })
}

///|
async test "osc dynamic color responses are stream events" {
  with_input(
    b"\x1b]10;rgb:ffff/0000/7fff\x07\x1b]11;rgb:ff/00/80\x1b\\\x1b]12;rgb:f/0/abc\x07",
    events => {
      @debug.assert_eq(
        events.read_event(),
        DynamicColor(code=10, red=65535, green=0, blue=32767),
      )
      @debug.assert_eq(
        events.read_event(),
        DynamicColor(code=11, red=65535, green=0, blue=32896),
      )
      @debug.assert_eq(
        events.read_event(),
        DynamicColor(code=12, red=65535, green=0, blue=43978),
      )
    },
  )
}

///|
async test "invalid osc dynamic color shapes remain unknown input" {
  with_input(
    b"\x1b]10;?\x07\x1b]10;rgb:fffff/0/0\x07\x1b]13;rgb:ffff/0/0\x07\x1b]110;rgb:ffff/0/0\x07",
    events => {
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b]10;?\x07"))
      @debug.assert_eq(
        events.read_event(),
        input_unknown(b"\x1b]10;rgb:fffff/0/0\x07"),
      )
      @debug.assert_eq(
        events.read_event(),
        input_unknown(b"\x1b]13;rgb:ffff/0/0\x07"),
      )
      @debug.assert_eq(
        events.read_event(),
        input_unknown(b"\x1b]110;rgb:ffff/0/0\x07"),
      )
    },
  )
}

///|
async test "flush osc introducer as alt right bracket" {
  with_delayed_input(b"\x1b]", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(
        @public_input.KeyEvent::new(
          Char(']'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
        ),
      ),
    )
  })
}

///|
async test "invalid private response shapes remain unknown input" {
  with_input(b"\x1b[?u\x1b[?1;2u\x1b[?c\x1b[?1;c", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?u"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?1;2u"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?c"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?1;c"))
  })
}

///|
async test "cursor position response can follow input event" {
  with_input(b"a\x1b[12;34R", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
    @debug.assert_eq(events.read_event(), CursorPosition(row=12, col=34))
  })
}

///|
async test "decode focus tracking reports" {
  with_input(b"\x1b[I\x1b[O\x1b[1I\x1b[?O", events => {
    @debug.assert_eq(events.read_event(), input_focus_in())
    @debug.assert_eq(events.read_event(), input_focus_out())
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1I"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?O"))
  })
}

///|
async test "decode printable ascii" {
  with_input(b"aA", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('A'), text="A")),
    )
  })
}

///|
async test "decode utf8 text" {
  with_input(b"\xc3\xa9\xe4\xbd\xa0\xf0\x9f\x98\x80", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('é'), text="é")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('你'), text="你")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('😀'), text="😀")),
    )
  })
}

///|
async test "decode split utf8 text" {
  with_delayed_input(b"\xe4", b"\xbd\xa0", 5, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=50),
      input_key(@public_input.KeyEvent::new(Char('你'), text="你")),
    )
  })
}

///|
async test "decode invalid utf8 as unknown and leaves ascii buffered" {
  with_input(b"\xe4a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xe4"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode invalid utf8 lead byte" {
  with_input(b"\xffa", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xff"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode malformed utf8 sequence" {
  with_input(b"\xe0\x80\x80a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xe0\x80\x80"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "flush incomplete utf8 as unknown" {
  with_delayed_input(b"\xe4", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\xe4"),
    )
  })
}

///|
async test "flush escape key" {
  with_delayed_input(b"\x1b", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
  })
}

///|
async test "decode delayed escape exposes csi mouse tail as text" {
  with_delayed_input(b"\x1b", b"[3;71M", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
    for char in "[3;71M" {
      @debug.assert_eq(
        events.read_event(esc_timeout_ms=10),
        input_key(@public_input.KeyEvent::new(Char(char), text=[char])),
      )
    }
  })
}

///|
async test "decode delayed escape exposes sgr mouse tail as text" {
  with_delayed_input(b"\x1b", b"[<3;71;12M", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
    for char in "[<3;71;12M" {
      @debug.assert_eq(
        events.read_event(esc_timeout_ms=10),
        input_key(@public_input.KeyEvent::new(Char(char), text=[char])),
      )
    }
  })
}

///|
async test "decode delayed sgr mouse prefix consumes csi prefix as unknown" {
  with_delayed_input(b"\x1b[<", b"3;71;12M", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\x1b[<"),
    )
    for char in "3;71;12M" {
      @debug.assert_eq(
        events.read_event(esc_timeout_ms=10),
        input_key(@public_input.KeyEvent::new(Char(char), text=[char])),
      )
    }
  })
}

///|
async test "decode escape followed by non printable byte" {
  with_input(b"\x1b\x80", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b\x80"))
  })
}

///|
async test "decode split csi arrow" {
  with_delayed_input(b"\x1b[", b"A", 5, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=50),
      input_key(@public_input.KeyEvent::new(Up)),
    )
  })
}

///|
async test "cancelled read_event preserves buffered bytes" {
  with_delayed_input(b"\x1b[", b"A", 50, events => {
    let result = @async.with_timeout_opt(10, () => {
      events.read_event(esc_timeout_ms=100)
    })
    @debug.assert_eq(result, None)
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=100),
      input_key(@public_input.KeyEvent::new(Up)),
    )
  })
}

///|
async test "decode control bytes" {
  with_input(b"\n\t\x7f\x08\x00\x01\x1a\x1c\x1f", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('j'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Tab)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Backspace)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Backspace)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char(' '),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('a'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('z'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('4'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('7'),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
  })
}

///|
async test "decode csi tilde key" {
  with_input(b"\x1b[3~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Delete)),
    )
  })
}

///|
async test "decode ss3 cursor and function keys" {
  with_input(b"\x1bOA\x1bOP", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Up)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F1)),
    )
  })
}

///|
async test "decode ss3 cursor variants" {
  with_input(b"\x1bOB\x1bOC\x1bOD\x1bOH\x1bOF", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Down)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Right)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Left)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(End)),
    )
  })
}

///|
async test "decode ss3 function variants and unknown" {
  with_input(b"\x1bOQ\x1bOR\x1bOS\x1bOX", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F2)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F3)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F4)),
    )
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1bOX"))
  })
}

///|
async test "flush incomplete ss3 as unknown" {
  with_delayed_input(b"\x1bO", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\x1bO"),
    )
  })
}

///|
async test "decode ss3 before repeated escape" {
  with_delayed_input(b"\x1bO\x1b", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\x1bO"),
    )
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
  })
}

///|
async test "decode csi function and home end variants" {
  with_input(b"\x1b[1~\x1b[8~\x1b[15~\x1b[24~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(End)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F5)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F12)),
    )
  })
}

///|
async test "decode csi direct key variants" {
  with_input(b"\x1b[Z\x1b[B\x1b[C\x1b[D\x1b[H\x1b[F\x1b[Q\x1b[R\x1b[S", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Tab,
          modifiers=@public_input.KeyModifiers::new(shift=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Down)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Right)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Left)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(End)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F2)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F3)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(F4)),
    )
  })
}

///|
async test "decode csi tilde variants" {
  with_input(
    b"\x1b[2~\x1b[5~\x1b[6~\x1b[11~\x1b[12~\x1b[13~\x1b[14~\x1b[17~\x1b[18~\x1b[19~\x1b[20~\x1b[21~\x1b[23~",
    events => {
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(Insert)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(PageUp)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(PageDown)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F1)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F2)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F3)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F4)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F6)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F7)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F8)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F9)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F10)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@public_input.KeyEvent::new(F11)),
      )
    },
  )
}

///|
async test "decode csi tilde key with empty modifier parameter" {
  with_input(b"\x1b[2;~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Insert)),
    )
  })
}

///|
async test "decode csi key modifiers" {
  with_input(b"\x1b[1;5A\x1b[3;5~\x1b[1;2P", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Up,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Delete,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          F1,
          modifiers=@public_input.KeyModifiers::new(shift=true),
        ),
      ),
    )
  })
}

///|
async test "decode legacy and kitty csi key modifier mappings separately" {
  with_input(b"\x1b[1;9A\x1b[3;9~\x1b[1;9:2A", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Up,
          modifiers=@public_input.KeyModifiers::new(meta=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Delete,
          modifiers=@public_input.KeyModifiers::new(meta=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Up,
          modifiers=@public_input.KeyModifiers::new(super_=true),
          kind=Repeat,
        ),
      ),
    )
  })
}

///|
async test "decode csi zero modifier as no modifiers" {
  with_input(b"\x1b[1;0A\x1b[3;0~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Up)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Delete)),
    )
  })
}

///|
async test "decode sgr mouse event kinds" {
  with_input(
    b"\x1b[<0;20;10M\x1b[<0;20;10m\x1b[<32;21;11M\x1b[<35;22;12M\x1b[<64;23;13M\x1b[<65;24;14M\x1b[<66;25;15M\x1b[<67;26;16M",
    events => {
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Press(Left), 10, 20)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Release(Left), 10, 20)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Drag(Left), 11, 21)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Move, 12, 22)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Scroll(Up), 13, 23)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Scroll(Down), 14, 24)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Scroll(Left), 15, 25)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Scroll(Right), 16, 26)),
      )
    },
  )
}

///|
async test "decode sgr mouse buttons modifiers and optional trailing semicolon" {
  with_input(
    b"\x1b[<1;2;3M\x1b[<2;4;5M\x1b[<4;6;7M\x1b[<10;8;9M\x1b[<18;10;11M\x1b[<30;12;13;M",
    events => {
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Press(Middle), 3, 2)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(@public_input.MouseEvent::new(Press(Right), 5, 4)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(
          @public_input.MouseEvent::new(
            Press(Left),
            7,
            6,
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(
          @public_input.MouseEvent::new(
            Press(Right),
            9,
            8,
            modifiers=@public_input.KeyModifiers::new(alt=true),
          ),
        ),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(
          @public_input.MouseEvent::new(
            Press(Right),
            11,
            10,
            modifiers=@public_input.KeyModifiers::new(ctrl=true),
          ),
        ),
      )
      @debug.assert_eq(
        events.read_event(),
        input_mouse(
          @public_input.MouseEvent::new(
            Press(Right),
            13,
            12,
            modifiers=@public_input.KeyModifiers::new(
              shift=true,
              alt=true,
              ctrl=true,
            ),
          ),
        ),
      )
    },
  )
}

///|
async test "decode invalid sgr mouse reports as unknown" {
  with_input(
    b"\x1b[<0;0;10M\x1b[<0;20;0M\x1b[<3;20;10M\x1b[<128;20;10M\x1b[<256;20;10M\x1b[<0;20M\x1b[<0;20;10;1M\x1b[<64;10;10m\x1b[<32;10;10m",
    events => {
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<0;0;10M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<0;20;0M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<3;20;10M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<128;20;10M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<256;20;10M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<0;20M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<0;20;10;1M"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<64;10;10m"))
      @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[<32;10;10m"))
    },
  )
}

///|
async test "decode csi m as unknown without consuming next input" {
  with_input(b"\x1b[Mabc", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[M"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('b'), text="b")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('c'), text="c")),
    )
  })
}

///|
async test "decode alt key" {
  with_input(b"\x1bx\x1bX", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('x'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @public_input.KeyEvent::new(
          Char('X'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
        ),
      ),
    )
  })
}

///|
async test "flush alt left bracket" {
  with_delayed_input(b"\x1b[", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(
        @public_input.KeyEvent::new(
          Char('['),
          modifiers=@public_input.KeyModifiers::new(alt=true),
        ),
      ),
    )
  })
}

///|
async test "flush incomplete csi as unknown" {
  with_delayed_input(b"\x1b[12;", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\x1b[12;"),
    )
  })
}

///|
async test "decode invalid csi parameter shapes as unknown" {
  with_input(b"\x1b[?~\x1b[?A\x1b[1;2;3A\x1b[1;2;3~\x1b[ 1\x1b[\x80", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?~"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[?A"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1;2;3A"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1;2;3~"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[ 1"))
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[\x80"))
  })
}

///|
async test "decode unsupported csi final as unknown" {
  with_input(b"\x1b[1za", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1z"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode long csi grows event buffer" {
  with_input(b"\x1b[1234567890~a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1234567890~"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode multiple events with repeated calls" {
  with_input(b"a\r", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Enter)),
    )
  })
}

///|
async test "decode unsupported csi as unknown and leaves following bytes buffered" {
  with_input(b"\x1b[999~a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[999~"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode bracketed paste as one input event" {
  with_input(b"\x1b[200~hello\x1b[201~a", events => {
    @debug.assert_eq(events.read_event(), input_paste("hello"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@public_input.KeyEvent::new(Char('a'), text="a")),
    )
  })
}

///|
async test "decode bracketed paste payload without nested key parsing" {
  with_input(b"\x1b[200~o\x1b[2D\r\x1b[201~", events => {
    @debug.assert_eq(events.read_event(), input_paste("o\u{1B}[2D\r"))
  })
}

///|
async test "decode invalid utf8 bracketed paste as unknown" {
  with_input(b"\x1b[200~\xff\x1b[201~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_unknown(b"\x1b[200~\xff\x1b[201~"),
    )
  })
}

///|
async test "decode unclosed bracketed paste as unknown after timeout" {
  with_delayed_input(b"\x1b[200~hello", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_unknown(b"\x1b[200~hello"),
    )
  })
}

///|
async test "decode repeated escape as two escape events" {
  with_delayed_input(b"\x1b\x1b", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@public_input.KeyEvent::new(Escape)),
    )
  })
}
