///|
test "sgr sequences" {
  @debug.assert_eq(@vt.sgr1(0), b"\x1b[0m")
  @debug.assert_eq(@vt.sgr3(38, 5, 42), b"\x1b[38;5;42m")
  @debug.assert_eq(@vt.sgr5(38, 2, 1, 127, 255), b"\x1b[38;2;1;127;255m")
}
