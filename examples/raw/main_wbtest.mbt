///|
test "byte to raw line prints printable ascii char" {
  assert_true(byte_to_raw_line(b'\x00') == "0x00\r\n")
  assert_true(byte_to_raw_line(b'a') == "0x61 'a'\r\n")
  assert_true(byte_to_raw_line(b' ') == "0x20 ' '\r\n")
  assert_true(byte_to_raw_line(b'\\') == "0x5c '\\\\'\r\n")
  assert_true(byte_to_raw_line(b'\xab') == "0xab\r\n")
}
