///|
test "erase line sequences" {
  @debug.assert_eq(@vt.erase_line_right, b"\x1b[K")
  @debug.assert_eq(@vt.erase_line_left, b"\x1b[1K")
  @debug.assert_eq(@vt.erase_line_all, b"\x1b[2K")
}
