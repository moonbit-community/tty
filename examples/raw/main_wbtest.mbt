///|
test "byte to hex line" {
  assert_true(byte_to_hex_line(b'\x00') == b"0x00\r\n")
  assert_true(byte_to_hex_line(b'\xab') == b"0xab\r\n")
  assert_true(byte_to_hex_line(b'\xff') == b"0xff\r\n")
}
