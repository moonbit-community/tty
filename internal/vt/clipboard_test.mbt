///|
test "set clipboard sequence base64-encodes the text" {
  @debug.assert_eq(@vt.set_clipboard("hello"), b"\x1b]52;c;aGVsbG8=\x1b\\")
}

///|
test "set clipboard sequence encodes the text as UTF-8 first" {
  @debug.assert_eq(@vt.set_clipboard("你好"), b"\x1b]52;c;5L2g5aW9\x1b\\")
}

///|
test "set clipboard sequence with empty text has an empty payload" {
  @debug.assert_eq(@vt.set_clipboard(""), b"\x1b]52;c;\x1b\\")
}

///|
test "write set clipboard appends to the buffer" {
  let buf = @buffer.Buffer()
  buf.write_bytes(b"x")
  @vt.write_set_clipboard(buf, "hello")
  @debug.assert_eq(buf.to_bytes(), b"x\x1b]52;c;aGVsbG8=\x1b\\")
}
