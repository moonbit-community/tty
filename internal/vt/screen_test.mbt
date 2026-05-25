///|
test "alternate screen sequences" {
  @debug.assert_eq(@vt.enter_alt_screen, b"\x1b[?1049h")
  @debug.assert_eq(@vt.leave_alt_screen, b"\x1b[?1049l")
}

///|
test "bracketed paste sequences" {
  @debug.assert_eq(@vt.enable_bracketed_paste, b"\x1b[?2004h")
  @debug.assert_eq(@vt.disable_bracketed_paste, b"\x1b[?2004l")
}

///|
test "terminal response query sequences" {
  @debug.assert_eq(@vt.query_keyboard_enhancement_flags, b"\x1b[?u")
  @debug.assert_eq(@vt.request_primary_device_attributes, b"\x1b[c")
}
