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
async test "decode printable ascii" {
  with_input(b"aA", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('A'), text="A")),
    )
  })
}

///|
async test "decode utf8 text" {
  with_input(b"\xc3\xa9\xe4\xbd\xa0\xf0\x9f\x98\x80", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('é'), text="é")),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('你'), text="你")),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('😀'), text="😀")),
    )
  })
}

///|
async test "decode split utf8 text" {
  with_delayed_input(b"\xe4", b"\xbd\xa0", 5, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout=50),
      @input.Key(@input.KeyEvent::new(@input.Char('你'), text="你")),
    )
  })
}

///|
async test "decode invalid utf8 as unknown and leaves ascii buffered" {
  with_input(b"\xe4a", events => {
    @debug.assert_eq(events.read_event(), @input.Unknown(b"\xe4"))
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "flush incomplete utf8 as unknown" {
  with_delayed_input(b"\xe4", b"", 50, events => {
    @debug.assert_eq(events.read_event(esc_timeout=10), @input.Unknown(b"\xe4"))
  })
}

///|
async test "flush escape key" {
  with_delayed_input(b"\x1b", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout=10),
      @input.Key(@input.KeyEvent::new(@input.Escape)),
    )
  })
}

///|
async test "decode split csi arrow" {
  with_delayed_input(b"\x1b[", b"A", 5, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout=50),
      @input.Key(@input.KeyEvent::new(@input.Up)),
    )
  })
}

///|
async test "decode csi tilde key" {
  with_input(b"\x1b[3~", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Delete)),
    )
  })
}

///|
async test "decode ss3 cursor and function keys" {
  with_input(b"\x1bOA\x1bOP", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Up)),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.F1)),
    )
  })
}

///|
async test "decode csi function and home end variants" {
  with_input(b"\x1b[1~\x1b[8~\x1b[15~\x1b[24~", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Home)),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.End)),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.F5)),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.F12)),
    )
  })
}

///|
async test "decode csi key modifiers" {
  with_input(b"\x1b[1;5A\x1b[3;5~\x1b[1;2P", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(
        @input.KeyEvent::new(
          @input.Up,
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(
        @input.KeyEvent::new(
          @input.Delete,
          modifiers=@input.KeyModifiers::new(ctrl=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(
        @input.KeyEvent::new(
          @input.F1,
          modifiers=@input.KeyModifiers::new(shift=true),
        ),
      ),
    )
  })
}

///|
async test "decode alt key" {
  with_input(b"\x1bx\x1bX", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(
        @input.KeyEvent::new(
          @input.Char('x'),
          modifiers=@input.KeyModifiers::new(alt=true),
        ),
      ),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(
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
      events.read_event(esc_timeout=10),
      @input.Key(
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
      events.read_event(esc_timeout=10),
      @input.Unknown(b"\x1b[12;"),
    )
  })
}

///|
async test "decode multiple events with repeated calls" {
  with_input(b"a\r", events => {
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Enter)),
    )
  })
}

///|
async test "decode unsupported csi as unknown and leaves following bytes buffered" {
  with_input(b"\x1b[999~a", events => {
    @debug.assert_eq(events.read_event(), @input.Unknown(b"\x1b[999~"))
    @debug.assert_eq(
      events.read_event(),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "decode repeated escape as two escape events" {
  with_delayed_input(b"\x1b\x1b", b"", 50, events => {
    @debug.assert_eq(
      events.read_event(esc_timeout=10),
      @input.Key(@input.KeyEvent::new(@input.Escape)),
    )
    @debug.assert_eq(
      events.read_event(esc_timeout=10),
      @input.Key(@input.KeyEvent::new(@input.Escape)),
    )
  })
}
