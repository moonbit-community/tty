///|
test "decode printable ascii" {
  let decoder = @input.Decoder::new()
  decoder.push(b"a")
  @debug.assert_eq(
    decoder.next(),
    Some(@input.Key(@input.KeyEvent::new(@input.Char('a'), text="a"))),
  )
  @debug.assert_eq(decoder.next(), None)
}

///|
test "flush escape key" {
  let decoder = @input.Decoder::new()
  decoder.push(b"\x1b")
  @debug.assert_eq(decoder.next(), None)
  @debug.assert_eq(
    decoder.flush(),
    Some(@input.Key(@input.KeyEvent::new(@input.Escape))),
  )
  @debug.assert_eq(decoder.next(), None)
}

///|
test "decode split csi arrow" {
  let decoder = @input.Decoder::new()
  decoder.push(b"\x1b[")
  @debug.assert_eq(decoder.next(), None)
  decoder.push(b"A")
  @debug.assert_eq(
    decoder.next(),
    Some(@input.Key(@input.KeyEvent::new(@input.Up))),
  )
}

///|
test "decode csi tilde key" {
  let decoder = @input.Decoder::new()
  decoder.push(b"\x1b[3~")
  @debug.assert_eq(
    decoder.next(),
    Some(@input.Key(@input.KeyEvent::new(@input.Delete))),
  )
}

///|
test "decode alt key" {
  let decoder = @input.Decoder::new()
  decoder.push(b"\x1bx")
  @debug.assert_eq(
    decoder.next(),
    Some(
      @input.Key(
        @input.KeyEvent::new(
          @input.Char('x'),
          modifiers=@input.KeyModifiers::new(alt=true),
        ),
      ),
    ),
  )
}

///|
test "flush incomplete csi as unknown" {
  let decoder = @input.Decoder::new()
  decoder.push(b"\x1b[12;")
  @debug.assert_eq(decoder.next(), None)
  @debug.assert_eq(decoder.flush(), Some(@input.Unknown(b"\x1b[12;")))
}

///|
test "parse_to drains complete events" {
  let decoder = @input.Decoder::new()
  let events : Array[@input.Event] = Array::new()
  decoder.parse_to(b"a\r", events)
  @debug.assert_eq(events.length(), 2)
  @debug.assert_eq(
    events[0],
    @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
  )
  @debug.assert_eq(events[1], @input.Key(@input.KeyEvent::new(@input.Enter)))
}

///|
test "parse_to keeps escape pending until flush_to" {
  let decoder = @input.Decoder::new()
  let events : Array[@input.Event] = Array::new()
  decoder.parse_to(b"\x1b", events)
  @debug.assert_eq(events.length(), 0)
  decoder.flush_to(events)
  @debug.assert_eq(events.length(), 1)
  @debug.assert_eq(events[0], @input.Key(@input.KeyEvent::new(@input.Escape)))
}

///|
test "parse_to emits unsupported csi as unknown and continues" {
  let decoder = @input.Decoder::new()
  let events : Array[@input.Event] = Array::new()
  decoder.parse_to(b"\x1b[999~a", events)
  @debug.assert_eq(events.length(), 2)
  @debug.assert_eq(events[0], @input.Unknown(b"\x1b[999~"))
  @debug.assert_eq(
    events[1],
    @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
  )
}
