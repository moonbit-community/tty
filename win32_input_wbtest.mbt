///|
#cfg(platform="windows")
fn win32_test_key_record(
  char : Char,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> @win32.KeyRecord {
  @win32.KeyRecord::new(
    key_down~,
    repeat_count=1,
    virtual_key_code~,
    virtual_scan_code=0,
    unicode_char=char.to_int(),
    control_key_state~,
  )
}

///|
#cfg(platform="windows")
fn win32_test_key_record_charcode(
  charcode : Int,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> @win32.KeyRecord {
  @win32.KeyRecord::new(
    key_down~,
    repeat_count=1,
    virtual_key_code~,
    virtual_scan_code=0,
    unicode_char=charcode,
    control_key_state~,
  )
}

///|
#cfg(platform="windows")
fn win32_test_mouse_record(
  x? : Int = 0,
  y? : Int = 0,
  button_state? : Int = 0,
  control_key_state? : Int = 0,
  event_flags? : Int = 0,
) -> @win32.MouseRecord {
  @win32.MouseRecord::new(
    x~,
    y~,
    button_state~,
    control_key_state~,
    event_flags~,
  )
}

///|
#cfg(platform="windows")
fn[I : Reader, O : Writer] win32_test_console_tty(input : I, output : O) -> Tty {
  let input = input as &Reader
  let output = output as &Writer
  let input_backend = WindowsInput::console(input.fd())
  {
    input,
    output,
    reader: input_backend.event_reader(input as &@async/io.Reader),
    input_backend,
    pending_input: [],
    write_lock: @lock.Lock::new(),
  }
}

///|
#cfg(platform="windows")
fn win32_test_try_get_event(tty : Tty) -> Event? {
  match tty.input_backend {
    Console(events~, ..) =>
      try events.try_get() catch {
        _ => None
      } noraise {
        event => event
      }
    ByteStream => None
  }
}

///|
#cfg(platform="windows")
async test "win32 console source ignores key-up records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(win32_test_key_record('a', key_down=0))
  match win32_test_try_get_event(source) {
    None => ()
    Some(_) => fail("expected key-up record to be ignored")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source decodes bracketed paste key records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  for char in "\u{1B}[200~hello\u{1B}[201~" {
    source.read_key_record(win32_test_key_record(char))
  }
  match source.read_decoded_input_event(50) {
    Input(Paste(text)) => @debug.assert_eq(text, "hello")
    _ => fail("expected bracketed paste event")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source preserves native events during internal reads" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_record(Focus(true))
  for char in "\u{1B}[7;9R" {
    source.read_key_record(win32_test_key_record(char))
  }
  match source.reader.read_event(esc_timeout_ms=50) {
    CursorPosition(row~, col~) => {
      @debug.assert_eq(row, 7)
      @debug.assert_eq(col, 9)
    }
    _ => fail("expected cursor position event")
  }
  match win32_test_try_get_event(source) {
    Some(Input(FocusIn)) => ()
    _ => fail("expected native focus event to remain queued")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source keeps queued bytes after native event" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_record(Focus(true))
  for char in "\u{1B}[<0;20;4M" {
    source.read_key_record(win32_test_key_record(char))
  }
  match win32_test_try_get_event(source) {
    Some(Input(FocusIn)) => ()
    _ => fail("expected native focus event to remain queued")
  }
  match source.read_decoded_input_event(50) {
    Input(Mouse(event)) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Press(Left), 4, 20))
    _ => fail("expected complete queued SGR mouse event")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source maps native mouse records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, event_flags=@win32.MouseMoved),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Move, 3, 31))
    _ => fail("expected mouse move event")
  }
  source.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, button_state=@win32.MouseLeftButton),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Press(Left), 3, 31))
    _ => fail("expected left mouse press event")
  }
  source.read_mouse_record(
    win32_test_mouse_record(
      x=31,
      y=2,
      button_state=@win32.MouseLeftButton,
      control_key_state=@win32.ShiftPressed,
      event_flags=@win32.MouseMoved,
    ),
  )
  match win32_test_try_get_event(source) {
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
  source.read_mouse_record(win32_test_mouse_record(x=31, y=2))
  match win32_test_try_get_event(source) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(
        event,
        @public_input.MouseEvent::new(Release(Left), 3, 32),
      )
    _ => fail("expected left mouse release event")
  }
  source.read_mouse_record(
    win32_test_mouse_record(
      x=31,
      y=2,
      button_state=120 * 0x10000,
      event_flags=@win32.MouseWheeled,
    ),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Scroll(Up), 3, 32))
    _ => fail("expected mouse wheel up event")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source preserves printable key modifiers" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record('a', control_key_state=@win32.LeftAltPressed),
  )
  match win32_test_try_get_event(source) {
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
  source.read_key_record(
    win32_test_key_record(
      'X',
      control_key_state=@win32.ShiftPressed | @win32.RightAltPressed,
    ),
  )
  match win32_test_try_get_event(source) {
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
#cfg(platform="windows")
async test "win32 console source preserves ctrl left bracket" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '\u{1B}',
      virtual_key_code=0xdb,
      control_key_state=@win32.LeftCtrlPressed,
    ),
  )
  match win32_test_try_get_event(source) {
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
#cfg(platform="windows")
async test "win32 console source preserves ctrl space" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record_charcode(
      0,
      virtual_key_code=0x20,
      control_key_state=@win32.LeftCtrlPressed,
    ),
  )
  match win32_test_try_get_event(source) {
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
#cfg(platform="windows")
async test "win32 console source preserves AltGr text input" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '@',
      control_key_state=@win32.RightAltPressed | @win32.LeftCtrlPressed,
    ),
  )
  match source.read_decoded_input_event(50) {
    Input(Key(event)) =>
      @debug.assert_eq(event, @public_input.KeyEvent::new(Char('@'), text="@"))
    _ => fail("expected decoded AltGr text key event")
  }
}

///|
#cfg(platform="windows")
async test "win32 console source preserves keypad key metadata" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '1',
      virtual_key_code=0x61,
      control_key_state=@win32.NumLockOn,
    ),
  )
  match win32_test_try_get_event(source) {
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
  source.read_key_record(win32_test_key_record('*', virtual_key_code=0x6a))
  match win32_test_try_get_event(source) {
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
#cfg(platform="windows")
async test "win32 console source preserves keypad enter metadata" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '\r',
      virtual_key_code=0x0d,
      control_key_state=@win32.EnhancedKey,
    ),
  )
  match win32_test_try_get_event(source) {
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
#cfg(platform="windows")
async test "win32 console source preserves keypad navigation metadata" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record_charcode(0, virtual_key_code=0x23),
  )
  match win32_test_try_get_event(source) {
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
  source.read_key_record(
    win32_test_key_record_charcode(
      0,
      virtual_key_code=0x23,
      control_key_state=@win32.EnhancedKey,
    ),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(event, @public_input.KeyEvent::new(End))
    _ => fail("expected enhanced End key event")
  }
}
