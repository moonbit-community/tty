///|
fn written(write : (@buffer.Buffer) -> Unit) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  write(buf)
  buf.to_bytes()
}

///|
test "write cursor sequences" {
  @debug.assert_eq(
    written(buf => @vt.write_cursor_up(buf, 1)),
    @vt.cursor_up(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_up(buf, 12)),
    @vt.cursor_up(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_down(buf, 1)),
    @vt.cursor_down(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_down(buf, 12)),
    @vt.cursor_down(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_forward(buf, 1)),
    @vt.cursor_forward(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_forward(buf, 12)),
    @vt.cursor_forward(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_back(buf, 1)),
    @vt.cursor_back(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_back(buf, 12)),
    @vt.cursor_back(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_next_line(buf, 1)),
    @vt.cursor_next_line(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_next_line(buf, 12)),
    @vt.cursor_next_line(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_prev_line(buf, 1)),
    @vt.cursor_prev_line(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_prev_line(buf, 12)),
    @vt.cursor_prev_line(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_horizontal_absolute(buf, 1)),
    @vt.cursor_horizontal_absolute(1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_horizontal_absolute(buf, 12)),
    @vt.cursor_horizontal_absolute(12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_position(buf, 1, 1)),
    @vt.cursor_position(1, 1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_cursor_position(buf, 3, 4)),
    @vt.cursor_position(3, 4),
  )
}

///|
test "write sgr sequences" {
  @debug.assert_eq(written(buf => @vt.write_sgr1(buf, 0)), @vt.sgr1(0))
  @debug.assert_eq(
    written(buf => @vt.write_sgr3(buf, 38, 5, 42)),
    @vt.sgr3(38, 5, 42),
  )
  @debug.assert_eq(
    written(buf => @vt.write_sgr5(buf, 38, 2, 1, 127, 255)),
    @vt.sgr5(38, 2, 1, 127, 255),
  )
}

///|
test "write color sequences" {
  @debug.assert_eq(
    written(buf => @vt.write_set_foreground(buf, Default)),
    @vt.set_foreground(Default),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_foreground(buf, Basic(Red))),
    @vt.set_foreground(Basic(Red)),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_foreground(buf, Indexed(42))),
    @vt.set_foreground(Indexed(42)),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_foreground(buf, Rgb(-1, 127, 999))),
    @vt.set_foreground(Rgb(-1, 127, 999)),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_background(buf, Default)),
    @vt.set_background(Default),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_background(buf, Basic(Red))),
    @vt.set_background(Basic(Red)),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_background(buf, Indexed(42))),
    @vt.set_background(Indexed(42)),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_background(buf, Rgb(-1, 127, 999))),
    @vt.set_background(Rgb(-1, 127, 999)),
  )
}

///|
test "write keyboard and scroll sequences" {
  @debug.assert_eq(
    written(buf => @vt.write_push_keyboard_enhancement_flags(buf, 31)),
    @vt.push_keyboard_enhancement_flags(31),
  )
  @debug.assert_eq(
    written(buf => @vt.write_push_keyboard_enhancement_flags(buf, -1)),
    @vt.push_keyboard_enhancement_flags(-1),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_top_bottom_margins(buf, 4, 12)),
    @vt.set_top_bottom_margins(4, 12),
  )
  @debug.assert_eq(
    written(buf => @vt.write_set_top_bottom_margins(buf, 8, 3)),
    @vt.set_top_bottom_margins(8, 3),
  )
}
