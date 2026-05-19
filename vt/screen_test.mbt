///|
test "alternate screen sequences" {
  @debug.assert_eq(@vt.enter_alt_screen, b"\x1b[?1049h")
  @debug.assert_eq(@vt.leave_alt_screen, b"\x1b[?1049l")
}
