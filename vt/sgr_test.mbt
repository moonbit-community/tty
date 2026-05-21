///|
test "sgr sequences" {
  @debug.assert_eq(@vt.bold, b"\x1b[1m")
  @debug.assert_eq(@vt.reset_bold, b"\x1b[22m")
  @debug.assert_eq(@vt.italic, b"\x1b[3m")
  @debug.assert_eq(@vt.reset_italic, b"\x1b[23m")
  @debug.assert_eq(@vt.underline, b"\x1b[4m")
  @debug.assert_eq(@vt.reset_underline, b"\x1b[24m")
  @debug.assert_eq(@vt.reverse, b"\x1b[7m")
  @debug.assert_eq(@vt.reset_reverse, b"\x1b[27m")
  @debug.assert_eq(@vt.sgr1(0), b"\x1b[0m")
  @debug.assert_eq(@vt.sgr3(38, 5, 42), b"\x1b[38;5;42m")
  @debug.assert_eq(@vt.sgr5(38, 2, 1, 127, 255), b"\x1b[38;2;1;127;255m")
}
