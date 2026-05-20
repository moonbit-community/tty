///|
test "editor starts at end and keeps cursor visible" {
  let editor = Editor::from_text("a\nb\nc")
  let point = editor.cursor_point()
  inspect(point.line, content="2")
  inspect(point.grapheme_column, content="1")
  inspect(point.display_column, content="1")
  inspect(editor.view_start, content="1")
  inspect(editor_cursor_row(editor), content="1")
}

///|
test "editor up down moves cursor and scrolls viewport" {
  let bottom = Editor::from_text("one\ntwo\nthree")
  inspect(bottom.cursor_point().line, content="2")
  inspect(bottom.view_start, content="1")
  let up1 = bottom.move_vertical(-1)
  inspect(up1.cursor_point().line, content="1")
  inspect(up1.cursor_point().display_column, content="3")
  inspect(up1.view_start, content="1")
  let up2 = up1.move_vertical(-1)
  inspect(up2.cursor_point().line, content="0")
  inspect(up2.cursor_point().display_column, content="3")
  inspect(up2.view_start, content="0")
  let down1 = up2.move_vertical(1)
  inspect(down1.cursor_point().line, content="1")
  inspect(down1.view_start, content="0")
  let down2 = down1.move_vertical(1)
  inspect(down2.cursor_point().line, content="2")
  inspect(down2.view_start, content="1")
}

///|
test "editor inserts and deletes at cursor" {
  let inserted = Editor::from_text("ab").move_left().insert("X")
  inspect(inserted.text, content="aXb")
  inspect(inserted.cursor, content="2")
  let deleted_before = Editor::from_text("a👨‍👩‍👧‍👦b")
    .move_left()
    .delete_before()
  inspect(deleted_before.text, content="ab")
  inspect(deleted_before.cursor_point().display_column, content="1")
  let deleted_after = Editor::from_text("ab").move_home().delete_after()
  inspect(deleted_after.text, content="b")
  inspect(deleted_after.cursor, content="0")
}

///|
test "editor home end moves within logical line" {
  let editor = Editor::from_text("ab\ncd")
  let home = editor.move_home()
  inspect(home.cursor_point().line, content="1")
  inspect(home.cursor_point().display_column, content="0")
  let end = home.move_end()
  inspect(end.cursor_point().line, content="1")
  inspect(end.cursor_point().display_column, content="2")
}

///|
test "input prefix marks only the first logical input line" {
  inspect(input_prefix(0, 0), content="> ")
  inspect(input_prefix(1, 0), content="  ")
  inspect(input_prefix(0, 1), content="  ")
}

///|
test "input cursor offset accounts for prompt and display width" {
  inspect(input_cursor_offset(Editor::new(), 80), content="2")
  inspect(input_cursor_offset(Editor::from_text("abc"), 80), content="5")
  inspect(input_cursor_offset(Editor::from_text("你好"), 80), content="6")
  inspect(
    input_cursor_offset(Editor::from_text("abc").move_left(), 80),
    content="4",
  )
  inspect(input_cursor_offset(Editor::from_text("a\nb"), 80), content="3")
  inspect(input_cursor_offset(Editor::from_text("abcdef"), 5), content="5")
}

///|
test "fit line respects display width and graphemes" {
  inspect(fit_line("abcdef", 3), content="abc")
  inspect(fit_line("你好世界", 4), content="你好")
  inspect(
    fit_line("x👨‍👩‍👧‍👦y", 3),
    content="x👨‍👩‍👧‍👦",
  )
}

///|
test "split input lines keeps trailing input row" {
  inspect(split_input_lines("a\nb\n").join("|"), content="a|b|")
}

///|
test "fake response echoes input" {
  inspect(fake_response("hello"), content="received: hello")
  inspect(fake_response("hello\nworld"), content="received: hello / world")
}

///|
test "text from key ignores modified control keys" {
  let text = text_from_key(
    @tty/input.KeyEvent::new(@tty/input.Char('x'), text="x"),
  )
  assert_true(text == Some("x"))
  assert_true(
    text_from_key(
      @tty/input.KeyEvent::new(
        @tty/input.Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ) ==
    None,
  )
}

///|
test "ctrl j is newline key" {
  assert_true(
    is_newline_key(
      @tty/input.KeyEvent::new(
        @tty/input.Char('j'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
  assert_false(is_newline_key(@tty/input.KeyEvent::new(@tty/input.Enter)))
}
