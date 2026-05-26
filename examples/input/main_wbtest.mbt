///|
test "display width counts wide and emoji graphemes" {
  inspect(display_width("abc"), content="3")
  inspect(display_width("你好"), content="4")
  inspect(display_width("👨‍👩‍👧‍👦"), content="2")
}

///|
test "delete last grapheme" {
  inspect(delete_last_grapheme(""), content="")
  inspect(delete_last_grapheme("ab"), content="a")
  inspect(delete_last_grapheme("a你"), content="a")
  inspect(delete_last_grapheme("e\u{0301}"), content="")
  inspect(delete_last_grapheme("x👨‍👩‍👧‍👦"), content="x")
}

///|
test "describe bytes" {
  inspect(byte_to_hex(b'\x00'), content="0x00")
  inspect(byte_to_hex(b'\xab'), content="0xab")
  inspect(describe_bytes(b"\x00\x7f\xff"), content="0x00 0x7f 0xff")
}

///|
test "describe modifiers" {
  inspect(describe_modifiers(@tty/input.KeyModifiers::new()), content="")
  inspect(
    describe_modifiers(
      @tty/input.KeyModifiers::new(shift=true, alt=true, ctrl=true, meta=true),
    ),
    content="Ctrl+Alt+Shift+Meta+",
  )
}

///|
test "describe key names" {
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Char('x'))),
    content="event: Key x",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Text)),
    content="event: Key Text",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Enter)),
    content="event: Key Enter",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Tab)),
    content="event: Key Tab",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Backspace)),
    content="event: Key Backspace",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Delete)),
    content="event: Key Delete",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Escape)),
    content="event: Key Escape",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Up)),
    content="event: Key Up",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Down)),
    content="event: Key Down",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Left)),
    content="event: Key Left",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Right)),
    content="event: Key Right",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Home)),
    content="event: Key Home",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.End)),
    content="event: Key End",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.PageUp)),
    content="event: Key PageUp",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.PageDown)),
    content="event: Key PageDown",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.Insert)),
    content="event: Key Insert",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F1)),
    content="event: Key F1",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F2)),
    content="event: Key F2",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F3)),
    content="event: Key F3",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F4)),
    content="event: Key F4",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F5)),
    content="event: Key F5",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F6)),
    content="event: Key F6",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F7)),
    content="event: Key F7",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F8)),
    content="event: Key F8",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F9)),
    content="event: Key F9",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F10)),
    content="event: Key F10",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(@tty/input.F11)),
    content="event: Key F11",
  )
  inspect(
    describe_key(
      @tty/input.KeyEvent::new(
        @tty/input.F12,
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
    content="event: Key Ctrl+F12",
  )
}

///|
test "describe mouse events" {
  inspect(describe_mouse_button(@tty/input.Left), content="Left")
  inspect(describe_mouse_button(@tty/input.Middle), content="Middle")
  inspect(describe_mouse_button(@tty/input.Right), content="Right")
  inspect(describe_mouse_scroll(@tty/input.Up), content="Up")
  inspect(describe_mouse_scroll(@tty/input.Down), content="Down")
  inspect(describe_mouse_scroll(@tty/input.Left), content="Left")
  inspect(describe_mouse_scroll(@tty/input.Right), content="Right")
  inspect(
    describe_mouse_kind(@tty/input.Press(@tty/input.Left)),
    content="Press Left",
  )
  inspect(
    describe_mouse_kind(@tty/input.Release(@tty/input.Middle)),
    content="Release Middle",
  )
  inspect(
    describe_mouse_kind(@tty/input.Drag(@tty/input.Right)),
    content="Drag Right",
  )
  inspect(describe_mouse_kind(@tty/input.Move), content="Move")
  inspect(
    describe_mouse_kind(@tty/input.Scroll(@tty/input.Down)),
    content="Scroll Down",
  )
  inspect(
    describe_mouse(
      @tty/input.MouseEvent::new(
        @tty/input.Press(@tty/input.Left),
        10,
        20,
        modifiers=@tty/input.KeyModifiers::new(shift=true),
      ),
    ),
    content="event: Mouse Shift+Press Left row=10 col=20",
  )
}
