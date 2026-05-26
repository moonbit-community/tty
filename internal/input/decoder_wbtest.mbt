///|
test "ensure capacity handles zero sized buffer" {
  let (reader, writer) = @io.pipe()
  defer reader.close()
  defer writer.close()
  let events = EventReader::{
    reader,
    data: FixedArray::make(0, b'\x00'),
    head: 0,
    read: 0,
    tail: 0,
  }
  events.ensure_capacity(1)
  @debug.assert_eq(events.data.length(), EventReaderInitialBufferCapacity)
}

///|
test "parse csi rejects malformed private input" {
  @debug.assert_eq(parse_csi([]), Input(Unknown(b"")))
}

///|
test "text event preserves multi character text" {
  @debug.assert_eq(
    text_event("ab"),
    Key(@public_input.KeyEvent::new(Text, text="ab")),
  )
}
