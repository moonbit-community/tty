///|
test "cursor movement sequences" {
  inspect(@vt.cursor_up(1), content="b\"\\x1b[A\"")
  inspect(@vt.cursor_up(12), content="b\"\\x1b[12A\"")
  inspect(@vt.cursor_down(1), content="b\"\\x1b[B\"")
  inspect(@vt.cursor_down(12), content="b\"\\x1b[12B\"")
}

///|
test "cursor visibility sequences" {
  inspect(@vt.hide_cursor, content="b\"\\x1b[?25l\"")
  inspect(@vt.show_cursor, content="b\"\\x1b[?25h\"")
}
