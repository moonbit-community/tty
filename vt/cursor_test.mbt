///|
test "cursor movement sequences" {
  @debug.assert_eq(@vt.cursor_up(1), b"\x1b[A")
  @debug.assert_eq(@vt.cursor_up(12), b"\x1b[12A")
  @debug.assert_eq(@vt.cursor_down(1), b"\x1b[B")
  @debug.assert_eq(@vt.cursor_down(12), b"\x1b[12B")
  @debug.assert_eq(@vt.cursor_forward(1), b"\x1b[C")
  @debug.assert_eq(@vt.cursor_forward(12), b"\x1b[12C")
  @debug.assert_eq(@vt.cursor_back(1), b"\x1b[D")
  @debug.assert_eq(@vt.cursor_back(12), b"\x1b[12D")
  @debug.assert_eq(@vt.cursor_next_line(1), b"\x1b[E")
  @debug.assert_eq(@vt.cursor_next_line(12), b"\x1b[12E")
  @debug.assert_eq(@vt.cursor_prev_line(1), b"\x1b[F")
  @debug.assert_eq(@vt.cursor_prev_line(12), b"\x1b[12F")
  @debug.assert_eq(@vt.cursor_horizontal_absolute(1), b"\x1b[G")
  @debug.assert_eq(@vt.cursor_horizontal_absolute(12), b"\x1b[12G")
  @debug.assert_eq(@vt.cursor_position(1, 1), b"\x1b[H")
  @debug.assert_eq(@vt.cursor_position(0, 0), b"\x1b[H")
  @debug.assert_eq(@vt.cursor_position(0, 4), b"\x1b[1;4H")
  @debug.assert_eq(@vt.cursor_position(3, 0), b"\x1b[3;1H")
  @debug.assert_eq(@vt.request_cursor_position, b"\x1b[6n")
}

///|
test "cursor visibility sequences" {
  @debug.assert_eq(@vt.hide_cursor, b"\x1b[?25l")
  @debug.assert_eq(@vt.show_cursor, b"\x1b[?25h")
}
