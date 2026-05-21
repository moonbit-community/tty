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
fn input_key(key : @input.KeyEvent) -> @input.Event {
  @input.Input(@input.Key(key))
}

///|
fn input_unknown(bytes : Bytes) -> @input.Event {
  @input.Input(@input.Unknown(bytes))
}

///|
fn input_paste(text : String) -> @input.Event {
  @input.Input(@input.Paste(text))
}

///|
test "key modifier accessors" {
  let modifiers = @input.KeyModifiers::new(
    shift=true,
    alt=true,
    ctrl=true,
    meta=true,
  )
  @debug.assert_eq(modifiers.shift(), true)
  @debug.assert_eq(modifiers.alt(), true)
  @debug.assert_eq(modifiers.ctrl(), true)
  @debug.assert_eq(modifiers.meta(), true)
  let none = @input.KeyModifiers::new()
  @debug.assert_eq(none.shift(), false)
  @debug.assert_eq(none.alt(), false)
  @debug.assert_eq(none.ctrl(), false)
  @debug.assert_eq(none.meta(), false)
}

///|
async test "cursor position response is a stream event" {
  with_input(b"\x1b[12;34R", events => {
    @debug.assert_eq(events.read_event(), @input.CursorPosition(row=12, col=34))
  })
}

///|
async test "cursor position response can follow input event" {
  with_input(b"a\x1b[12;34R", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(events.read_event(), @input.CursorPosition(row=12, col=34))
  })
}

///|
async test "decode printable ascii" {
  with_input(b"aA", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('A'), text="A")),
    )
  })
}

///|
async test "decode utf8 text" {
  with_input(b"\xc3\xa9\xe4\xbd\xa0\xf0\x9f\x98\x80", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('é'), text="é")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('你'), text="你")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('😀'), text="😀")),
    )
  })
}

///|
async test "decode split utf8 text" {
  with_delayed_input(b"\xe4", b"\xbd\xa0", 5, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=50),
      input_key(@input.KeyEvent::new(@input.Char('你'), text="你")),
    )
  })
}

///|
async test "decode invalid utf8 as unknown and leaves ascii buffered" {
  with_input(b"\xe4a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xe4"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode invalid utf8 lead byte" {
  with_input(b"\xffa", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xff"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode malformed utf8 sequence" {
  with_input(b"\xe0\x80\x80a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\xe0\x80\x80"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
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
      input_key(@input.KeyEvent::new(@input.Escape)),
    )
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
      input_key(@input.KeyEvent::new(@input.Up)),
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
      input_key(@input.KeyEvent::new(@input.Up)),
    )
  })
}

///|
async test "decode control bytes" {
  with_input(b"\n\t\x7f\x08\x00\x01\x1a\x1c\x1f", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('j'),
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Tab)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Backspace)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Backspace)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char(' '),
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('a'),
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('z'),
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('4'),
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('7'),
          modifiers=@input.KeyModifiers::new(ctrl=true),
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
      input_key(@input.KeyEvent::new(@input.Delete)),
    )
  })
}

///|
async test "decode ss3 cursor and function keys" {
  with_input(b"\x1bOA\x1bOP", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Up)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F1)),
    )
  })
}

///|
async test "decode ss3 cursor variants" {
  with_input(b"\x1bOB\x1bOC\x1bOD\x1bOH\x1bOF", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Down)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Right)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Left)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.End)),
    )
  })
}

///|
async test "decode ss3 function variants and unknown" {
  with_input(b"\x1bOQ\x1bOR\x1bOS\x1bOX", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F2)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F3)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F4)),
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
      input_key(@input.KeyEvent::new(@input.Escape)),
    )
  })
}

///|
async test "decode csi function and home end variants" {
  with_input(b"\x1b[1~\x1b[8~\x1b[15~\x1b[24~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.End)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F5)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F12)),
    )
  })
}

///|
async test "decode csi direct key variants" {
  with_input(b"\x1b[Z\x1b[B\x1b[C\x1b[D\x1b[H\x1b[F\x1b[Q\x1b[R\x1b[S", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Tab,
          modifiers=@input.KeyModifiers::new(shift=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Down)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Right)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Left)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.End)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F2)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F3)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.F4)),
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
        input_key(@input.KeyEvent::new(@input.Insert)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.PageUp)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.PageDown)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F1)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F2)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F3)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F4)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F6)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F7)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F8)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F9)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F10)),
      )
      @debug.assert_eq(
        events.read_event(),
        input_key(@input.KeyEvent::new(@input.F11)),
      )
    },
  )
}

///|
async test "decode csi tilde key with empty modifier parameter" {
  with_input(b"\x1b[2;~", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Insert)),
    )
  })
}

///|
async test "decode csi key modifiers" {
  with_input(b"\x1b[1;5A\x1b[3;5~\x1b[1;2P", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Up,
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Delete,
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.F1,
          modifiers=@input.KeyModifiers::new(shift=true),
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
      input_key(@input.KeyEvent::new(@input.Up)),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Delete)),
    )
  })
}

///|
async test "decode alt key" {
  with_input(b"\x1bx\x1bX", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('x'),
          modifiers=@input.KeyModifiers::new(alt=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(
        @input.KeyEvent::new(
          @input.Char('X'),
          modifiers=@input.KeyModifiers::new(alt=true),
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
        @input.KeyEvent::new(
          @input.Char('['),
          modifiers=@input.KeyModifiers::new(alt=true),
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
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode long csi grows event buffer" {
  with_input(b"\x1b[1234567890~a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[1234567890~"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode multiple events with repeated calls" {
  with_input(b"a\r", events => {
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Enter)),
    )
  })
}

///|
async test "decode unsupported csi as unknown and leaves following bytes buffered" {
  with_input(b"\x1b[999~a", events => {
    @debug.assert_eq(events.read_event(), input_unknown(b"\x1b[999~"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode bracketed paste as one input event" {
  with_input(b"\x1b[200~hello\x1b[201~a", events => {
    @debug.assert_eq(events.read_event(), input_paste("hello"))
    @debug.assert_eq(
      events.read_event(),
      input_key(@input.KeyEvent::new(@input.Char('a'), text="a")),
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
      input_key(@input.KeyEvent::new(@input.Escape)),
    )
    @debug.assert_eq(
      events.read_event(esc_timeout_ms=10),
      input_key(@input.KeyEvent::new(@input.Escape)),
    )
  })
}
