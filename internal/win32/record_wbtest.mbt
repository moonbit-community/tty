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
test "win32 raw input record parses key records" {
  let buf = test_raw_record(RecordKey)
  test_set_u32_le(buf, 4, 1)
  test_set_u16_le(buf, 8, 2)
  test_set_u16_le(buf, 10, 0x41)
  test_set_u16_le(buf, 12, 0x1e)
  test_set_u16_le(buf, 14, 'A'.to_int())
  test_set_u32_le(buf, 16, ShiftPressed)
  match test_input_record(buf) {
    Key(record) => {
      @debug.assert_eq(record.key_down, 1)
      @debug.assert_eq(record.repeat_count, 2)
      @debug.assert_eq(record.virtual_key_code, 0x41)
      @debug.assert_eq(record.virtual_scan_code, 0x1e)
      @debug.assert_eq(record.unicode_char, 'A'.to_int())
      @debug.assert_eq(record.control_key_state, ShiftPressed)
    }
    _ => fail("expected key record")
  }
}

///|
test "win32 raw input record parses mouse records" {
  let buf = test_raw_record(RecordMouse)
  test_set_u16_le(buf, 4, 30)
  test_set_u16_le(buf, 6, 2)
  test_set_u32_le(buf, 8, MouseLeftButton)
  test_set_u32_le(buf, 12, ShiftPressed)
  test_set_u32_le(buf, 16, MouseMoved)
  match test_input_record(buf) {
    Mouse(record) => {
      @debug.assert_eq(record.x, 30)
      @debug.assert_eq(record.y, 2)
      @debug.assert_eq(record.button_state, MouseLeftButton)
      @debug.assert_eq(record.control_key_state, ShiftPressed)
      @debug.assert_eq(record.event_flags, MouseMoved)
    }
    _ => fail("expected mouse record")
  }
}
