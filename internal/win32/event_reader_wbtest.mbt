///|
fn test_console_reader() -> EventReader raise {
  let (read, write) = @async/pipe.pipe()
  defer read.close()
  defer write.close()
  EventReader::new(read.fd())
}

///|
fn feed_console_text(reader : EventReader, text : String) -> Unit raise {
  for char in text {
    reader.read_record(Character(code_unit=char.to_int(), repeat_count=1))
  }
}

///|
test "native records expose only character payload and resize" {
  // Key-down A with Shift and a virtual key. Metadata is deliberately absent
  // from the resulting transport record.
  let bytes = b"\x01\x00\x00\x00\x01\x00\x00\x00\x02\x00\x41\x00\x1e\x00\x41\x00\x10\x00\x00\x00"
  guard InputRecord::parse(bytes) is Character(code_unit=65, repeat_count=2) else {
    fail("expected repeated character payload")
  }
  guard InputRecord::parse(b"\x04\x00\x00\x00\x50\x00\x18\x00") is Resize else {
    fail("expected resize")
  }
  for
    bytes in [
      b"\x02\x00", b"\x10\x00", b"\x01", b"\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x41\x00\x1e\x00\x41\x00",
    ] {
    guard InputRecord::parse(bytes) is Ignored else {
      fail("expected ignored record")
    }
  }
}

///|
async test "native characters all use the byte decoder" {
  let reader = test_console_reader()
  defer reader.close()
  feed_console_text(
    reader, "\u{1b}[65;30;65;1;16_\u{1b}[I\u{1b}[<0;20;4M\u{1b}[200~hello\u{1b}[201~",
  )
  assert_console_event(
    reader.read_decoded_input_event(50),
    Some(
      Input(
        Key(
          @public_input.KeyEvent::new(
            Char('A'),
            text="A",
            modifiers=@public_input.KeyModifiers::new(shift=true),
          ),
        ),
      ),
    ),
  )
  assert_console_event(
    reader.read_decoded_input_event(50),
    Some(Input(FocusIn)),
  )
  assert_console_event(
    reader.read_decoded_input_event(50),
    Some(Input(Mouse(@public_input.MouseEvent::new(Press(Left), 4, 20)))),
  )
  assert_console_event(
    reader.read_decoded_input_event(50),
    Some(Input(Paste("hello"))),
  )
}

///|
async test "native resize survives queries and coalesces" {
  let reader = test_console_reader()
  defer reader.close()
  reader.read_record(Resize)
  reader.read_record(Resize)
  feed_console_text(reader, "\u{1b}[7;9R")
  @debug.assert_eq(reader.decoder.read_event(), CursorPosition(row=7, col=9))
  assert_true(reader.resize_notifications.try_get() is Some(_))
  assert_true(reader.resize_notifications.try_get() is None)
}

///|
async test "resize cancellation retains a partial keyboard sequence" {
  let reader = test_console_reader()
  defer reader.close()
  feed_console_text(reader, "\u{1b}[65;30;")
  @async.with_task_group() <| group => {
    group.spawn_bg(() => {
      @async.sleep(5)
      reader.read_record(Resize)
    })
    assert_console_event(reader.read_input_event(100), Some(Resize))
  }
  feed_console_text(reader, "97;1_")
  assert_console_event(
    reader.read_input_event(50),
    Some(Input(Key(@public_input.KeyEvent::new(Char('a'), text="a")))),
  )
}

///|
async test "native UTF16 transport survives resize between surrogate halves" {
  let reader = test_console_reader()
  defer reader.close()
  reader.read_record(Character(code_unit=0xd83d, repeat_count=1))
  reader.read_record(Resize)
  reader.read_record(Ignored)
  reader.read_record(Character(code_unit=0xde00, repeat_count=1))
  assert_console_event(
    reader.read_decoded_input_event(50),
    Some(Input(Key(@public_input.KeyEvent::new(Char('😀'), text="😀")))),
  )
}

///|
async test "native wait remains cancellable" {
  let reader = test_console_reader()
  defer reader.close()
  assert_true(
    @async.with_timeout_opt(5, () => reader.read_input_event(50)) is None,
  )
  feed_console_text(reader, "a")
  assert_console_event(
    reader.read_input_event(50),
    Some(Input(Key(@public_input.KeyEvent::new(Char('a'), text="a")))),
  )
}

///|
fn assert_console_event(actual : Event?, expected : Event?) -> Unit raise {
  match (actual, expected) {
    (Some(Input(actual)), Some(Input(expected))) =>
      @debug.assert_eq(actual, expected)
    (Some(Resize), Some(Resize)) | (None, None) => ()
    _ => fail("unexpected console event kind")
  }
}
