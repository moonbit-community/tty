///|
/// Raw little-endian `KEY_EVENT` record for a key-down without a virtual key
/// code, as conhost synthesizes for its VT input translation.
fn raw_text_key(char : Char) -> Bytes {
  let buf = test_raw_record(RecordKey)
  test_set_u32_le(buf, 4, 1)
  test_set_u16_le(buf, 8, 1)
  test_set_u16_le(buf, 14, char.to_int())
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn raw_focus(focus_set : Bool) -> Bytes {
  let buf = test_raw_record(RecordFocus)
  test_set_u32_le(buf, 4, if focus_set { 1 } else { 0 })
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Decode `count` events from raw records written to a pipe in `chunks`, with
/// a short pause between chunks so a chunk boundary is also a read boundary.
async fn decode_raw_records(
  chunks : Array[Bytes],
  count~ : Int32,
) -> Array[@input.Event] {
  let events = []
  @async.with_task_group() <| group => {
    let (reader, writer) = @async/io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      for chunk in chunks {
        writer.write(chunk)
        @async.sleep(5)
      }
    }
    let decoder = @input.EventReader::new(RecordReader::new(reader))
    for _ in 0..<count {
      events.push(decoder.read_event())
    }
    reader.close()
  }
  events
}

///|
async test "record reader decodes raw records in order" {
  let records = @buffer.Buffer()
  records.write_bytes(raw_focus(true))
  for char in "\u{1B}[1;5D" {
    records.write_bytes(raw_text_key(char))
  }
  records.write_bytes(raw_focus(false))
  @debug.assert_eq(decode_raw_records([records.to_bytes()], count=3), [
    Input(FocusIn),
    Input(
      Key(
        @public_input.KeyEvent::new(
          Left,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      ),
    ),
    Input(FocusOut),
  ])
}

///|
async test "record reader keeps a record split across reads" {
  let record = raw_text_key('a')
  @debug.assert_eq(
    decode_raw_records([record[:7].to_owned(), record[7:].to_owned()], count=1),
    [Input(Key(@public_input.KeyEvent::new(Char('a'), text="a")))],
  )
}
