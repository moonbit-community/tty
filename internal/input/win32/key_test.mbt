///|
/// Build win32-input-mode parameters `Vk ; Sc ; Uc ; Kd ; Cs ; Rc`.
fn report(
  vk~ : Int32 = 0,
  uc~ : Int32 = 0,
  kd~ : Int32 = 1,
  cs~ : Int32 = 0,
  rc~ : Int32 = 1,
) -> Array[Int32?] {
  [Some(vk), Some(0), Some(uc), Some(kd), Some(cs), Some(rc)]
}

///|
test "parse printable keys with text" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc='a'.to_int())),
    Some(@public_input.KeyEvent::new(Char('a'), text="a")),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc='A'.to_int(), cs=0x0010)),
    Some(
      @public_input.KeyEvent::new(
        Char('A'),
        modifiers=@public_input.KeyModifiers::new(shift=true),
        text="A",
      ),
    ),
  )
}

///|
test "parse key kinds" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc='a'.to_int(), rc=3)),
    Some(@public_input.KeyEvent::new(Char('a'), kind=Repeat, text="a")),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc='a'.to_int(), kd=0)),
    Some(@public_input.KeyEvent::new(Char('a'), kind=Release)),
  )
}

///|
test "parse modified printable keys" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc='a'.to_int(), cs=0x0002)),
    Some(
      @public_input.KeyEvent::new(
        Char('a'),
        modifiers=@public_input.KeyModifiers::new(alt=true),
        text="a",
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x41, uc=0x01, cs=0x0008)),
    Some(
      @public_input.KeyEvent::new(
        Char('a'),
        modifiers=@public_input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
}

///|
test "parse ctrl keys without a character" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x20, cs=0x0008)),
    Some(
      @public_input.KeyEvent::new(
        Char(' '),
        modifiers=@public_input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0xdb, uc=0x1b, cs=0x0008)),
    Some(
      @public_input.KeyEvent::new(
        Escape,
        modifiers=@public_input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
}

///|
test "parse AltGr text without modifiers" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x51, uc='@'.to_int(), cs=0x0001 | 0x0008)),
    Some(@public_input.KeyEvent::new(Char('@'), text="@")),
  )
}

///|
test "parse named keys" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x26, cs=0x0100)),
    Some(@public_input.KeyEvent::new(Up)),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x25, cs=0x0100 | 0x0008)),
    Some(
      @public_input.KeyEvent::new(
        Left,
        modifiers=@public_input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x70)),
    Some(@public_input.KeyEvent::new(F1)),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x0d, uc='\r'.to_int())),
    Some(@public_input.KeyEvent::new(Enter)),
  )
}

///|
test "parse keypad keys" {
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x61, uc='1'.to_int(), cs=0x0020)),
    Some(
      @public_input.KeyEvent::new(
        Keypad1,
        state=@public_input.KeyEventState::new(keypad=true, num_lock=true),
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x0d, uc='\r'.to_int(), cs=0x0100)),
    Some(
      @public_input.KeyEvent::new(
        KeypadEnter,
        state=@public_input.KeyEventState::new(keypad=true),
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x23)),
    Some(
      @public_input.KeyEvent::new(
        End,
        state=@public_input.KeyEventState::new(keypad=true),
      ),
    ),
  )
  @debug.assert_eq(
    @win32.parse_key(report(vk=0x23, cs=0x0100)),
    Some(@public_input.KeyEvent::new(End)),
  )
}

///|
test "parse defaults and malformed reports" {
  @debug.assert_eq(
    @win32.parse_key([Some(0x26), None, None, Some(1), None, None]),
    Some(
      @public_input.KeyEvent::new(
        Up,
        state=@public_input.KeyEventState::new(keypad=true),
      ),
    ),
  )
  @debug.assert_eq(@win32.parse_key(report(vk=0x10, cs=0x0010)), None)
  @debug.assert_eq(@win32.parse_key([Some(0x26), Some(0), Some(0)]), None)
}
