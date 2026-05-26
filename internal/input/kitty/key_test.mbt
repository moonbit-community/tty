///|
test "parse key event kinds" {
  @debug.assert_eq(
    parse_key([[Some(97)]]),
    Some(@public_input.KeyEvent::new(Char('a'), text="a")),
  )
  @debug.assert_eq(
    parse_key([[Some(97)], [Some(1), Some(2)]]),
    Some(@public_input.KeyEvent::new(Char('a'), kind=Repeat, text="a")),
  )
  @debug.assert_eq(
    parse_key([[Some(97)], [Some(1), Some(3)]]),
    Some(@public_input.KeyEvent::new(Char('a'), kind=Release, text="a")),
  )
}

///|
test "parse modifiers alternate keys and associated text" {
  @debug.assert_eq(
    parse_key([[Some(105)], [Some(5)]]),
    Some(
      @public_input.KeyEvent::new(
        Char('i'),
        modifiers=@public_input.KeyModifiers::new(ctrl=true),
      ),
    ),
  )
  @debug.assert_eq(
    parse_key([[Some(61), Some(43)], [Some(6)]]),
    Some(
      @public_input.KeyEvent::new(
        Char('='),
        modifiers=@public_input.KeyModifiers::new(shift=true, ctrl=true),
        shifted_code=Char('+'),
      ),
    ),
  )
  @debug.assert_eq(
    parse_key([[Some(51)], [Some(2)]]),
    Some(
      @public_input.KeyEvent::new(
        Char('3'),
        modifiers=@public_input.KeyModifiers::new(shift=true),
      ),
    ),
  )
  @debug.assert_eq(
    parse_key([[Some(0)], [None], [Some(229)]]),
    Some(@public_input.KeyEvent::new(Text, text="å")),
  )
  @debug.assert_eq(
    parse_key([[Some(0)], [None], [Some(101), Some(769)]]),
    Some(@public_input.KeyEvent::new(Text, text="e\u{0301}")),
  )
}

///|
test "parse functional keys and extension event kinds" {
  @debug.assert_eq(
    parse_key([[Some(57400)]]),
    Some(
      @public_input.KeyEvent::new(
        Keypad1,
        state=@public_input.KeyEventState::new(keypad=true),
        text="1",
      ),
    ),
  )
  @debug.assert_eq(
    parse_key([[Some(57444)]]),
    Some(
      @public_input.KeyEvent::new(
        Modifier(LeftSuper),
        modifiers=@public_input.KeyModifiers::new(super_=true),
      ),
    ),
  )
  @debug.assert_eq(
    parse_key([[Some(57442)], [Some(1), Some(3)]]),
    Some(@public_input.KeyEvent::new(Modifier(LeftControl), kind=Release)),
  )
  match parse_csi_key_report([[Some(1)], [Some(5), Some(2)]]) {
    Some(report) =>
      @debug.assert_eq(
        report.key_event(Up),
        @public_input.KeyEvent::new(
          Up,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
          kind=Repeat,
        ),
      )
    None => fail("expected kitty modifier report")
  }
}

///|
test "invalid key shapes return none" {
  @debug.assert_eq(parse_key([]), None)
  @debug.assert_eq(parse_key([[None], [Some(5)]]), None)
  @debug.assert_eq(parse_key([[None, Some(43)]]), None)
  @debug.assert_eq(parse_key([[Some(0)]]), None)
  @debug.assert_eq(parse_key([[Some(1)]]), None)
  @debug.assert_eq(parse_key([[Some(0xE000)]]), None)
  @debug.assert_eq(parse_key([[Some(97), Some(65)], [Some(1)]]), None)
  @debug.assert_eq(parse_key([[Some(97), Some(0)], [Some(1)]]), None)
  @debug.assert_eq(parse_key([[Some(97), None, Some(0)]]), None)
  @debug.assert_eq(parse_key([[Some(97)], [Some(0)]]), None)
  @debug.assert_eq(parse_key([[Some(97)], [None, Some(2)]]), None)
  @debug.assert_eq(parse_key([[Some(97)], [Some(5), None]]), None)
  @debug.assert_eq(parse_key([[Some(97)], [None, None]]), None)
  @debug.assert_eq(parse_key([[Some(97)], [Some(5), Some(2), Some(9)]]), None)
  @debug.assert_eq(parse_key([[Some(97), Some(65), Some(99), Some(120)]]), None)
  @debug.assert_eq(
    parse_key([[Some(97)], [Some(1)], [Some(65), None, Some(66)]]),
    None,
  )
  @debug.assert_eq(parse_key([[Some(97)], [Some(1)], [Some(10)]]), None)
  @debug.assert_eq(
    parse_key([[Some(97)], [Some(1)], [Some(2)], [Some(3)]]),
    None,
  )
  @debug.assert_eq(parse_key([[Some(0)], [None], [Some(0x110000)]]), None)
}
