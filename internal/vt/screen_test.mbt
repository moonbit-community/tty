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

///|
test "mouse mode sequences" {
  @debug.assert_eq(@vt.enable_mouse_click, b"\x1b[?1000h")
  @debug.assert_eq(@vt.disable_mouse_click, b"\x1b[?1000l")
  @debug.assert_eq(@vt.enable_mouse_drag, b"\x1b[?1002h")
  @debug.assert_eq(@vt.disable_mouse_drag, b"\x1b[?1002l")
  @debug.assert_eq(@vt.enable_mouse_motion, b"\x1b[?1003h")
  @debug.assert_eq(@vt.disable_mouse_motion, b"\x1b[?1003l")
  @debug.assert_eq(@vt.enable_sgr_mouse, b"\x1b[?1006h")
  @debug.assert_eq(@vt.disable_sgr_mouse, b"\x1b[?1006l")
}
