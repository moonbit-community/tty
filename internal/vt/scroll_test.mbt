///|
test "scroll region sequence" {
  @debug.assert_eq(@vt.set_top_bottom_margins(1, 24), b"\x1b[1;24r")
  @debug.assert_eq(@vt.set_top_bottom_margins(4, 12), b"\x1b[4;12r")
}

///|
test "scroll region clamps low parameters" {
  @debug.assert_eq(@vt.set_top_bottom_margins(0, 0), b"\x1b[1;1r")
  @debug.assert_eq(@vt.set_top_bottom_margins(-2, 5), b"\x1b[1;5r")
  @debug.assert_eq(@vt.set_top_bottom_margins(8, 3), b"\x1b[8;8r")
}

///|
test "scroll control constants" {
  @debug.assert_eq(@vt.reset_top_bottom_margins, b"\x1b[r")
  @debug.assert_eq(@vt.reverse_index, b"\x1bM")
}
