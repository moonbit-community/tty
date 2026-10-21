///|
/// `dwControlKeyState` flags the encoder passes through without reading.
const NumLockOn : Int32 = 0x0020

///|
const EnhancedKey : Int32 = 0x0100

///|
fn key(
  char : Char,
  virtual_key_code~ : Int32 = 0,
  control_key_state~ : Int32 = 0,
  key_down~ : Int32 = 1,
  repeat_count~ : Int32 = 1,
) -> InputRecord {
  key_charcode(
    char.to_int(),
    virtual_key_code~,
    control_key_state~,
    key_down~,
    repeat_count~,
  )
}

///|
fn key_charcode(
  charcode : Int32,
  virtual_key_code~ : Int32 = 0,
  control_key_state~ : Int32 = 0,
  key_down~ : Int32 = 1,
  repeat_count~ : Int32 = 1,
) -> InputRecord {
  Key(
    KeyRecord::new(
      key_down~,
      repeat_count~,
      virtual_key_code~,
      virtual_scan_code=0,
      unicode_char=charcode,
      control_key_state~,
    ),
  )
}

///|
fn text_keys(text : String) -> Array[InputRecord] {
  [
    for char in text => key(char)
  ]
}

///|
fn mouse(
  x~ : Int32 = 0,
  y~ : Int32 = 0,
  button_state~ : Int32 = 0,
  control_key_state~ : Int32 = 0,
  event_flags~ : Int32 = 0,
) -> InputRecord {
  Mouse(
    MouseRecord::new(x~, y~, button_state~, control_key_state~, event_flags~),
  )
}

///|
fn encode_records(records : Array[InputRecord], vt_input~ : Bool) -> Bytes {
  let encoder = RecordEncoder::new()
  let out = @buffer.Buffer()
  for record in records {
    encoder.encode(record, vt_input~, out)
  }
  out.to_bytes()
}

///|
/// Encode records and decode `count` events from the bytes with the shared
/// terminal input decoder.
async fn decode_records(
  records : Array[InputRecord],
  vt_input~ : Bool,
  count~ : Int32 = 1,
) -> Array[@input.Event] {
  let bytes = encode_records(records, vt_input~)
  let events = []
  @async.with_task_group() <| group => {
    let (reader, writer) = @async/io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(bytes)
    }
    let decoder = @input.EventReader::new(reader)
    for _ in 0..<count {
      events.push(decoder.read_event())
    }
    reader.close()
  }
  events
}

///|
fn key_event(event : @public_input.KeyEvent) -> @input.Event {
  Input(Key(event))
}

///|
fn ctrl() -> @public_input.KeyModifiers {
  @public_input.KeyModifiers::new(ctrl=true)
}

///|
test "encoder drops key-up and lone modifier records" {
  @debug.assert_eq(encode_records([key('a', key_down=0)], vt_input=true), b"")
  @debug.assert_eq(
    encode_records(
      [key('a', virtual_key_code=0x41, key_down=0)],
      vt_input=false,
    ),
    b"",
  )
  @debug.assert_eq(
    encode_records(
      [
        key_charcode(0, virtual_key_code=0x10, control_key_state=ShiftPressed),
        key_charcode(
          0,
          virtual_key_code=0xa2,
          control_key_state=LeftCtrlPressed,
        ),
      ],
      vt_input=false,
    ),
    b"",
  )
}

///|
test "encoder writes VT input key text" {
  @debug.assert_eq(
    encode_records(
      [
        key('\u{1B}'),
        key('['),
        key('A'),
        key('x', virtual_key_code=0x58, control_key_state=ShiftPressed),
      ],
      vt_input=true,
    ),
    b"\x1b[Ax",
  )
  @debug.assert_eq(
    encode_records([key('z', repeat_count=3)], vt_input=true),
    b"zzz",
  )
}

///|
test "encoder joins UTF-16 surrogate pairs" {
  @debug.assert_eq(
    encode_records([key_charcode(0xd83d), key_charcode(0xde00)], vt_input=true),
    @utf8.encode("\u{1F600}"),
  )
  @debug.assert_eq(
    encode_records(
      [
        key_charcode(0xd83d, virtual_key_code=0xe7),
        key_charcode(0xde00, virtual_key_code=0xe7),
      ],
      vt_input=false,
    ),
    @utf8.encode("\u{1F600}"),
  )
  @debug.assert_eq(
    encode_records(
      [key_charcode(0xd83d), Focus(true), key_charcode(0xde00)],
      vt_input=true,
    ),
    b"\x1b[I",
  )
}

///|
test "encoder writes win32-input-mode reports without VT input" {
  @debug.assert_eq(
    encode_records(
      [
        Key(
          KeyRecord::new(
            virtual_key_code=0x41,
            virtual_scan_code=0x1e,
            unicode_char='a'.to_int(),
          ),
        ),
        key_charcode(
          0,
          virtual_key_code=0x26,
          control_key_state=EnhancedKey,
          repeat_count=2,
        ),
      ],
      vt_input=false,
    ),
    b"\x1b[65;30;97;1;0;1_\x1b[38;0;0;1;256;2_\x1b[38;0;0;1;256;2_",
  )
  @debug.assert_eq(encode_records([key('h'), key('i')], vt_input=false), b"hi")
}

///|
test "encoder writes SGR mouse reports" {
  @debug.assert_eq(
    encode_records(
      [
        mouse(x=30, y=2, event_flags=MouseMoved),
        mouse(x=30, y=2, button_state=MouseLeftButton),
        mouse(
          x=31,
          y=2,
          button_state=MouseLeftButton,
          control_key_state=ShiftPressed,
          event_flags=MouseMoved,
        ),
        mouse(x=31, y=2),
        mouse(x=31, y=2, button_state=120 * 0x10000, event_flags=MouseWheeled),
        mouse(x=31, y=2, button_state=-120 * 0x10000, event_flags=MouseWheeled),
        mouse(
          x=0,
          y=0,
          button_state=-120 * 0x10000,
          event_flags=MouseHorizontalWheeled,
        ),
      ],
      vt_input=true,
    ),
    b"\x1b[<35;31;3M\x1b[<0;31;3M\x1b[<36;32;3M\x1b[<0;32;3m\x1b[<64;32;3M\x1b[<65;32;3M\x1b[<66;1;1M",
  )
}

///|
test "encoder writes focus reports and no resize bytes" {
  @debug.assert_eq(
    encode_records(
      [Focus(true), WindowBufferSize, Focus(false), Unsupported],
      vt_input=true,
    ),
    b"\x1b[I\x1b[O",
  )
}

///|
async test "encoded records decode in record order" {
  let records = [Focus(true)]
  records.append(text_keys("\u{1B}[7;9R"))
  records.push(WindowBufferSize)
  records.push(mouse(x=19, y=3, button_state=MouseLeftButton))
  @debug.assert_eq(decode_records(records, vt_input=true, count=3), [
    Input(FocusIn),
    CursorPosition(row=7, col=9),
    Input(Mouse(@public_input.MouseEvent::new(Press(Left), 4, 20))),
  ])
}

///|
async test "encoded bracketed paste decodes as one paste event" {
  @debug.assert_eq(
    decode_records(text_keys("\u{1B}[200~hello\u{1B}[201~"), vt_input=true),
    [Input(Paste("hello"))],
  )
}

///|
async test "encoded mouse records decode to mouse events" {
  @debug.assert_eq(
    decode_records(
      [
        mouse(x=30, y=2, event_flags=MouseMoved),
        mouse(x=30, y=2, button_state=MouseLeftButton),
        mouse(
          x=31,
          y=2,
          button_state=MouseLeftButton,
          control_key_state=ShiftPressed,
          event_flags=MouseMoved,
        ),
        mouse(x=31, y=2),
        mouse(x=31, y=2, button_state=120 * 0x10000, event_flags=MouseWheeled),
      ],
      vt_input=true,
      count=5,
    ),
    [
      Input(Mouse(@public_input.MouseEvent::new(Move, 3, 31))),
      Input(Mouse(@public_input.MouseEvent::new(Press(Left), 3, 31))),
      Input(
        Mouse(
          @public_input.MouseEvent::new(
            Drag(Left),
            3,
            32,
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      ),
      Input(Mouse(@public_input.MouseEvent::new(Release(Left), 3, 32))),
      Input(Mouse(@public_input.MouseEvent::new(Scroll(Up), 3, 32))),
    ],
  )
}

///|
async test "encoded keys without VT input decode with key metadata" {
  @debug.assert_eq(
    decode_records(
      [
        key('a', virtual_key_code=0x41, control_key_state=LeftAltPressed),
        key('\u{1B}', virtual_key_code=0xdb, control_key_state=LeftCtrlPressed),
        key_charcode(
          0,
          virtual_key_code=0x20,
          control_key_state=LeftCtrlPressed,
        ),
        key(
          '@',
          virtual_key_code=0x51,
          control_key_state=RightAltPressed | LeftCtrlPressed,
        ),
        key('1', virtual_key_code=0x61, control_key_state=NumLockOn),
        key('\r', virtual_key_code=0x0d, control_key_state=EnhancedKey),
      ],
      vt_input=false,
      count=6,
    ),
    [
      key_event(
        @public_input.KeyEvent::new(
          Char('a'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
          text="a",
        ),
      ),
      key_event(@public_input.KeyEvent::new(Escape, modifiers=ctrl())),
      key_event(@public_input.KeyEvent::new(Char(' '), modifiers=ctrl())),
      key_event(@public_input.KeyEvent::new(Char('@'), text="@")),
      key_event(
        @public_input.KeyEvent::new(
          Keypad1,
          state=@public_input.KeyEventState::new(keypad=true, num_lock=true),
        ),
      ),
      key_event(
        @public_input.KeyEvent::new(
          KeypadEnter,
          state=@public_input.KeyEventState::new(keypad=true),
        ),
      ),
    ],
  )
}

///|
async test "encoded VT input keys decode like terminal bytes" {
  @debug.assert_eq(
    decode_records(
      [
        key('\u{1B}'),
        key('a'),
        key_charcode(0),
        key_charcode(0x1b),
        key('['),
        key('1'),
        key(';'),
        key('5'),
        key('D'),
      ],
      vt_input=true,
      count=2,
    ),
    [
      key_event(
        @public_input.KeyEvent::new(
          Char('a'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
        ),
      ),
      key_event(@public_input.KeyEvent::new(Left, modifiers=ctrl())),
    ],
  )
}

///|
fn test_console_reader() -> ConsoleReader raise {
  let (read, write) = @async/pipe.pipe()
  write.close()
  let reader = ConsoleReader::new(read.fd())
  read.close()
  reader
}

///|
async test "console reader reports resize records out of band" {
  let reader = test_console_reader()
  let out = @buffer.Buffer()
  reader.read_record(WindowBufferSize, vt_input=true, out)
  reader.read_record(key('a'), vt_input=true, out)
  reader.read_record(WindowBufferSize, vt_input=true, out)
  @debug.assert_eq(out.to_bytes(), b"a")
  guard @async.with_timeout_opt(10, () => reader.wait_resize()) is Some(_) else {
    fail("expected a resize notification")
  }
  guard @async.with_timeout_opt(10, () => reader.wait_resize()) is None else {
    fail("expected repeated resizes to coalesce into one notification")
  }
}
