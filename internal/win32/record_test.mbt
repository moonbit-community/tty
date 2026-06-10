///|
fn test_raw_record(event_type : Int) -> FixedArray[Byte] {
  let buf = FixedArray::make(20, b'\x00')
  test_set_u16_le(buf, 0, event_type)
  buf
}

///|
fn test_input_record(buf : FixedArray[Byte]) -> InputRecord {
  InputRecord::parse(buf.unsafe_reinterpret_as_bytes())
}

///|
fn test_set_u16_le(buf : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
}

///|
fn test_set_u32_le(buf : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
  buf[offset + 2] = ((value / 0x10000) & 0xff).to_byte()
  buf[offset + 3] = ((value / 0x1000000) & 0xff).to_byte()
}

///|
test "win32 raw input record parses focus records" {
  let buf = test_raw_record(RecordFocus)
  test_set_u32_le(buf, 4, 1)
  match test_input_record(buf) {
    Focus(true) => ()
    _ => fail("expected focus record")
  }
}

///|
test "win32 raw input record parses window buffer size records" {
  let buf = test_raw_record(RecordWindowBufferSize)
  test_set_u16_le(buf, 4, 80)
  test_set_u16_le(buf, 6, 24)
  match test_input_record(buf) {
    WindowBufferSize(_) => ()
    _ => fail("expected window buffer size record")
  }
}

///|
test "win32 raw input record parses unsupported records" {
  match InputRecord::parse(b"\x01") {
    Unsupported(0) => ()
    _ => fail("expected unsupported short record")
  }
  let buf = test_raw_record(0x1234)
  match test_input_record(buf) {
    Unsupported(0x1234) => ()
    _ => fail("expected unsupported record type")
  }
}

///|
test "win32 raw input record parses key records to input events" {
  let buf = test_raw_record(RecordKey)
  test_set_u32_le(buf, 4, 1)
  test_set_u16_le(buf, 8, 1)
  test_set_u16_le(buf, 10, 0x41)
  test_set_u16_le(buf, 12, 0x1e)
  test_set_u16_le(buf, 14, 'A'.to_int())
  test_set_u32_le(buf, 16, ShiftPressed)
  match test_input_record(buf) {
    Key(record) =>
      @debug.assert_eq(
        record.input(Ref(0)),
        Some(
          Key(
            @public_input.KeyEvent::new(
              Char('A'),
              modifiers=@public_input.KeyModifiers::new(shift=true),
              text="A",
            ),
          ),
        ),
      )
    _ => fail("expected key record")
  }
}

///|
test "win32 raw input record parses mouse records to input events" {
  let buf = test_raw_record(RecordMouse)
  test_set_u16_le(buf, 4, 30)
  test_set_u16_le(buf, 6, 2)
  test_set_u32_le(buf, 12, ShiftPressed)
  test_set_u32_le(buf, 16, MouseMoved)
  match test_input_record(buf) {
    Mouse(record) =>
      @debug.assert_eq(
        MouseButtonState::new().input_event(record),
        Some(
          Mouse(
            @public_input.MouseEvent::new(
              Move,
              3,
              31,
              modifiers=@public_input.KeyModifiers::new(shift=true),
            ),
          ),
        ),
      )
    _ => fail("expected mouse record")
  }
}
