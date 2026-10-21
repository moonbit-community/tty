///|
fn test_raw_record(event_type : Int32) -> FixedArray[Byte] {
  let buf = FixedArray::make(20, b'\x00')
  test_set_u16_le(buf, 0, event_type)
  buf
}

///|
fn test_input_record(buf : FixedArray[Byte]) -> @win32.InputRecord {
  @win32.InputRecord::parse(buf.unsafe_reinterpret_as_bytes())
}

///|
fn test_set_u16_le(
  buf : FixedArray[Byte],
  offset : Int32,
  value : Int32,
) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
}

///|
fn test_set_u32_le(
  buf : FixedArray[Byte],
  offset : Int32,
  value : Int32,
) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
  buf[offset + 2] = ((value / 0x10000) & 0xff).to_byte()
  buf[offset + 3] = ((value / 0x1000000) & 0xff).to_byte()
}

///|
test "win32 raw input record parses focus records" {
  let buf = test_raw_record(@win32.RecordFocus)
  test_set_u32_le(buf, 4, 1)
  match test_input_record(buf) {
    Focus(true) => ()
    _ => fail("expected focus record")
  }
}

///|
test "win32 raw input record parses window buffer size records" {
  let buf = test_raw_record(@win32.RecordWindowBufferSize)
  test_set_u16_le(buf, 4, 80)
  test_set_u16_le(buf, 6, 24)
  match test_input_record(buf) {
    WindowBufferSize(_) => ()
    _ => fail("expected window buffer size record")
  }
}

///|
test "win32 raw input record parses unsupported records" {
  match @win32.InputRecord::parse(b"\x01") {
    Unsupported(0) => ()
    _ => fail("expected unsupported short record")
  }
  let buf = test_raw_record(0x1234)
  match test_input_record(buf) {
    Unsupported(0x1234) => ()
    _ => fail("expected unsupported record type")
  }
}
