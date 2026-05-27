///|
test "string char count" {
  inspect(string_char_count("abc"), content="3")
  inspect(string_char_count("你好"), content="2")
  inspect(string_char_count("👨‍👩‍👧‍👦"), content="7")
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
    describe_key(@tty/input.KeyEvent::new(Char('x'))),
    content="event: Key x",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Text)),
    content="event: Key Text",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Enter)),
    content="event: Key Enter",
  )
  inspect(describe_key(@tty/input.KeyEvent::new(Tab)), content="event: Key Tab")
  inspect(
    describe_key(@tty/input.KeyEvent::new(Backspace)),
    content="event: Key Backspace",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Delete)),
    content="event: Key Delete",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Escape)),
    content="event: Key Escape",
  )
  inspect(describe_key(@tty/input.KeyEvent::new(Up)), content="event: Key Up")
  inspect(
    describe_key(@tty/input.KeyEvent::new(Down)),
    content="event: Key Down",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Left)),
    content="event: Key Left",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Right)),
    content="event: Key Right",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Home)),
    content="event: Key Home",
  )
  inspect(describe_key(@tty/input.KeyEvent::new(End)), content="event: Key End")
  inspect(
    describe_key(@tty/input.KeyEvent::new(PageUp)),
    content="event: Key PageUp",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(PageDown)),
    content="event: Key PageDown",
  )
  inspect(
    describe_key(@tty/input.KeyEvent::new(Insert)),
    content="event: Key Insert",
  )
  inspect(describe_key(@tty/input.KeyEvent::new(F1)), content="event: Key F1")
  inspect(describe_key(@tty/input.KeyEvent::new(F2)), content="event: Key F2")
  inspect(describe_key(@tty/input.KeyEvent::new(F3)), content="event: Key F3")
  inspect(describe_key(@tty/input.KeyEvent::new(F4)), content="event: Key F4")
  inspect(describe_key(@tty/input.KeyEvent::new(F5)), content="event: Key F5")
  inspect(describe_key(@tty/input.KeyEvent::new(F6)), content="event: Key F6")
  inspect(describe_key(@tty/input.KeyEvent::new(F7)), content="event: Key F7")
  inspect(describe_key(@tty/input.KeyEvent::new(F8)), content="event: Key F8")
  inspect(describe_key(@tty/input.KeyEvent::new(F9)), content="event: Key F9")
  inspect(describe_key(@tty/input.KeyEvent::new(F10)), content="event: Key F10")
  inspect(describe_key(@tty/input.KeyEvent::new(F11)), content="event: Key F11")
  inspect(
    describe_key(
      @tty/input.KeyEvent::new(
        F12,
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
    content="event: Key Ctrl+F12",
  )
}

///|
test "describe input events" {
  inspect(describe_input(Paste("hello")), content="event: Paste 5 chars")
  inspect(describe_input(FocusIn), content="event: FocusIn")
  inspect(describe_input(FocusOut), content="event: FocusOut")
  inspect(
    describe_input(Unknown(b"\x00\x7f")),
    content="event: Unknown 2 bytes [0x00 0x7f]",
  )
}

///|
test "describe mouse events" {
  inspect(describe_mouse_button(Left), content="Left")
  inspect(describe_mouse_button(Middle), content="Middle")
  inspect(describe_mouse_button(Right), content="Right")
  inspect(describe_mouse_scroll(Up), content="Up")
  inspect(describe_mouse_scroll(Down), content="Down")
  inspect(describe_mouse_scroll(Left), content="Left")
  inspect(describe_mouse_scroll(Right), content="Right")
  inspect(describe_mouse_kind(Press(Left)), content="Press Left")
  inspect(describe_mouse_kind(Release(Middle)), content="Release Middle")
  inspect(describe_mouse_kind(Drag(Right)), content="Drag Right")
  inspect(describe_mouse_kind(Move), content="Move")
  inspect(describe_mouse_kind(Scroll(Down)), content="Scroll Down")
  inspect(
    describe_mouse(
      @tty/input.MouseEvent::new(
        Press(Left),
        10,
        20,
        modifiers=@tty/input.KeyModifiers::new(shift=true),
      ),
    ),
    content="event: Mouse Shift+Press Left row=10 col=20",
  )
}

///|
test "describe terminal events" {
  inspect(
    describe_event(Input(Key(@tty/input.KeyEvent::new(Char('x'))))),
    content="event: Key x",
  )
  inspect(describe_event(Input(FocusIn)), content="event: FocusIn")
}
