///|
fn assert_decodes(bytes : Bytes, expected : @event.DecodeResult) -> Unit raise {
  @debug.assert_eq(@event.decode_one(bytes), expected)
}

///|
fn key(
  code : @event.KeyCode,
  consumed? : Int = 1,
  modifiers? : @event.KeyModifiers = @event.no_modifiers,
  text? : String = "",
) -> @event.DecodeResult {
  @event.Decoded(
    consumed,
    @event.Key(@event.KeyEvent::new(code, modifiers~, text~)),
  )
}

///|
test "decode printable text" {
  assert_decodes(b"a", key(@event.Char('a'), text="a"))
  assert_decodes(b"A", key(@event.Char('A'), text="A"))
  assert_decodes(
    @utf8.encode("你"),
    key(@event.Char('你'), consumed=3, text="你"),
  )
}

///|
test "decode control keys" {
  assert_decodes(b"\r", key(@event.Enter))
  assert_decodes(b"\n", key(@event.Char('j'), modifiers=@event.mod_ctrl))
  assert_decodes(b"\t", key(@event.Tab))
  assert_decodes(b"\x7f", key(@event.Backspace))
  assert_decodes(b"\x08", key(@event.Char('h'), modifiers=@event.mod_ctrl))
  assert_decodes(b"\x03", key(@event.Char('c'), modifiers=@event.mod_ctrl))
}

///|
test "decode escape ambiguity" {
  @debug.assert_eq(@event.decode_one(b"\x1b"), @event.NeedMore)
  @debug.assert_eq(@event.decode_one(b"\x1b", more=false), key(@event.Escape))
  @debug.assert_eq(
    @event.decode_one(b"\x1ba"),
    @event.Decoded(
      2,
      @event.Key(
        @event.KeyEvent::new(@event.Char('a'), modifiers=@event.mod_alt),
      ),
    ),
  )
}

///|
test "decode csi keys" {
  @debug.assert_eq(
    @event.decode_one(b"\x1b[A"),
    @event.Decoded(3, @event.Key(@event.KeyEvent::new(@event.Up))),
  )
  @debug.assert_eq(
    @event.decode_one(b"\x1b[1;2D"),
    @event.Decoded(
      6,
      @event.Key(@event.KeyEvent::new(@event.Left, modifiers=@event.mod_shift)),
    ),
  )
  @debug.assert_eq(
    @event.decode_one(b"\x1b[Z"),
    @event.Decoded(
      3,
      @event.Key(@event.KeyEvent::new(@event.Tab, modifiers=@event.mod_shift)),
    ),
  )
  @debug.assert_eq(
    @event.decode_one(b"\x1b[3~"),
    @event.Decoded(4, @event.Key(@event.KeyEvent::new(@event.Delete))),
  )
  @debug.assert_eq(@event.decode_one(b"\x1b["), @event.NeedMore)
}

///|
test "decode invalid utf8 as unknown" {
  @debug.assert_eq(
    @event.decode_one(b"\xff"),
    @event.Decoded(1, @event.Unknown(b"\xff")),
  )
}
