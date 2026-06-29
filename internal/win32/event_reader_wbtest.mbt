///|
fn win32_test_key_record(
  char : Char,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> KeyRecord {
  KeyRecord::new(
    key_down~,
    repeat_count=1,
    virtual_key_code~,
    virtual_scan_code=0,
    unicode_char=char.to_int(),
    control_key_state~,
  )
}

///|
fn win32_test_key_record_charcode(
  charcode : Int,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> KeyRecord {
  KeyRecord::new(
    key_down~,
    repeat_count=1,
    virtual_key_code~,
    virtual_scan_code=0,
    unicode_char=charcode,
    control_key_state~,
  )
}

///|
fn win32_test_mouse_record(
  x? : Int = 0,
  y? : Int = 0,
  button_state? : Int = 0,
  control_key_state? : Int = 0,
  event_flags? : Int = 0,
) -> MouseRecord {
  MouseRecord::new(x~, y~, button_state~, control_key_state~, event_flags~)
}

///|
fn win32_test_event_reader() -> EventReader raise {
  let (read, write) = @async/pipe.pipe()
  write.close()
  let reader = EventReader::new(read.fd())
  read.close()
  reader
}

///|
fn win32_test_try_get_event(reader : EventReader) -> Event? {
  try reader.events.try_get() catch {
    _ => None
  } noraise {
    event => event
  }
}

///|
async test "win32 event reader ignores key-up records" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(win32_test_key_record('a', key_down=0))
  match win32_test_try_get_event(reader) {
    None => ()
    Some(_) => fail("expected key-up record to be ignored")
  }
}

///|
async test "win32 event reader decodes bracketed paste key records" {
  let reader = win32_test_event_reader()
  defer reader.close()
  for char in "\u{1B}[200~hello\u{1B}[201~" {
    reader.read_key_record(win32_test_key_record(char))
  }
  match reader.read_decoded_input_event(50) {
    Some(Input(Paste(text))) => @debug.assert_eq(text, "hello")
    _ => fail("expected bracketed paste event")
  }
}

///|
async test "win32 event reader preserves native events during internal reads" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_record(Focus(true))
  for char in "\u{1B}[7;9R" {
    reader.read_key_record(win32_test_key_record(char))
  }
  match reader.decoder.read_event(esc_timeout_ms=50) {
    CursorPosition(row~, col~) => {
      @debug.assert_eq(row, 7)
      @debug.assert_eq(col, 9)
    }
    _ => fail("expected cursor position event")
  }
  match win32_test_try_get_event(reader) {
    Some(Input(FocusIn)) => ()
    _ => fail("expected native focus event to remain queued")
  }
}

///|
async test "win32 event reader propagates cancellation while waiting for native events" {
  let reader = win32_test_event_reader()
  defer reader.close()
  match @async.with_timeout_opt(1, () => reader.read_input_event(50)) {
    None => ()
    Some(_) => fail("expected timeout cancellation to propagate")
  }
}

///|
async test "win32 event reader keeps queued bytes after native event" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_record(Focus(true))
  for char in "\u{1B}[<0;20;4M" {
    reader.read_key_record(win32_test_key_record(char))
  }
  match win32_test_try_get_event(reader) {
    Some(Input(FocusIn)) => ()
    _ => fail("expected native focus event to remain queued")
  }
  match reader.read_decoded_input_event(50) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Press(Left), 4, 20))
    _ => fail("expected complete queued SGR mouse event")
  }
}

///|
async test "win32 event reader maps native mouse records" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, event_flags=MouseMoved),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Move, 3, 31))
    _ => fail("expected mouse move event")
  }
  reader.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, button_state=MouseLeftButton),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Press(Left), 3, 31))
    _ => fail("expected left mouse press event")
  }
  reader.read_mouse_record(
    win32_test_mouse_record(
      x=31,
      y=2,
      button_state=MouseLeftButton,
      control_key_state=ShiftPressed,
      event_flags=MouseMoved,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(
        event,
        @public_input.MouseEvent::new(
          Drag(Left),
          3,
          32,
          modifiers=@public_input.KeyModifiers::new(shift=true),
        ),
      )
    _ => fail("expected left mouse drag event")
  }
  reader.read_mouse_record(win32_test_mouse_record(x=31, y=2))
  match win32_test_try_get_event(reader) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(
        event,
        @public_input.MouseEvent::new(Release(Left), 3, 32),
      )
    _ => fail("expected left mouse release event")
  }
  reader.read_mouse_record(
    win32_test_mouse_record(
      x=31,
      y=2,
      button_state=120 * 0x10000,
      event_flags=MouseWheeled,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Scroll(Up), 3, 32))
    _ => fail("expected mouse wheel up event")
  }
}

///|
async test "win32 event reader preserves printable key modifiers" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record('a', control_key_state=LeftAltPressed),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          Char('a'),
          modifiers=@public_input.KeyModifiers::new(alt=true),
          text="a",
        ),
      )
    _ => fail("expected Alt+a key event")
  }
  reader.read_key_record(
    win32_test_key_record('X', control_key_state=ShiftPressed | RightAltPressed),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          Char('X'),
          modifiers=@public_input.KeyModifiers::new(shift=true, alt=true),
          text="X",
        ),
      )
    _ => fail("expected Shift+Alt+X key event")
  }
}

///|
async test "win32 event reader preserves ctrl left bracket" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record(
      '\u{1B}',
      virtual_key_code=0xdb,
      control_key_state=LeftCtrlPressed,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          Escape,
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    _ => fail("expected Ctrl+[ escape key event")
  }
}

///|
async test "win32 event reader preserves ctrl space" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record_charcode(
      0,
      virtual_key_code=0x20,
      control_key_state=LeftCtrlPressed,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          Char(' '),
          modifiers=@public_input.KeyModifiers::new(ctrl=true),
        ),
      )
    _ => fail("expected Ctrl+Space key event")
  }
}

///|
async test "win32 event reader preserves AltGr text input" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record(
      '@',
      control_key_state=RightAltPressed | LeftCtrlPressed,
    ),
  )
  match reader.read_decoded_input_event(50) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(event, @public_input.KeyEvent::new(Char('@'), text="@"))
    _ => fail("expected decoded AltGr text key event")
  }
}

///|
async test "win32 event reader preserves keypad key metadata" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record(
      '1',
      virtual_key_code=0x61,
      control_key_state=NumLockOn,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          Keypad1,
          state=@public_input.KeyEventState::new(keypad=true, num_lock=true),
        ),
      )
    _ => fail("expected keypad 1 key event")
  }
  reader.read_key_record(win32_test_key_record('*', virtual_key_code=0x6a))
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          KeypadMultiply,
          state=@public_input.KeyEventState::new(keypad=true),
        ),
      )
    _ => fail("expected keypad multiply key event")
  }
}

///|
async test "win32 event reader preserves keypad enter metadata" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record(
      '\r',
      virtual_key_code=0x0d,
      control_key_state=EnhancedKey,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          KeypadEnter,
          state=@public_input.KeyEventState::new(keypad=true),
        ),
      )
    _ => fail("expected keypad enter key event")
  }
}

///|
async test "win32 event reader preserves keypad navigation metadata" {
  let reader = win32_test_event_reader()
  defer reader.close()
  reader.read_key_record(
    win32_test_key_record_charcode(0, virtual_key_code=0x23),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(
        event,
        @public_input.KeyEvent::new(
          End,
          state=@public_input.KeyEventState::new(keypad=true),
        ),
      )
    _ => fail("expected keypad End key event")
  }
  reader.read_key_record(
    win32_test_key_record_charcode(
      0,
      virtual_key_code=0x23,
      control_key_state=EnhancedKey,
    ),
  )
  match win32_test_try_get_event(reader) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(event, @public_input.KeyEvent::new(End))
    _ => fail("expected enhanced End key event")
  }
}
