///|
#cfg(platform="windows")
fn win32_test_key_record(
  char : Char,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
) -> Win32InputRecord {
  {
    event_type: Win32RecordKey,
    key_down: 1,
    repeat_count: 1,
    virtual_key_code,
    unicode_char: char.to_int(),
    control_key_state,
    focus_set: 0,
  }
}

///|
#cfg(platform="windows")
fn win32_test_key_record_charcode(
  charcode : Int,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
) -> Win32InputRecord {
  {
    event_type: Win32RecordKey,
    key_down: 1,
    repeat_count: 1,
    virtual_key_code,
    unicode_char: charcode,
    control_key_state,
    focus_set: 0,
  }
}

///|
#cfg(platform="windows")
async test "win32 console source decodes bracketed paste key records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      for char in "\u{1B}[200~hello\u{1B}[201~" {
        source.read_key_record(win32_test_key_record(char))
      }
    }
    match source.read_decoded_input_event(50) {
      Input(Paste(text)) => @debug.assert_eq(text, "hello")
      _ => fail("expected bracketed paste event")
    }
  }
}

///|
#cfg(platform="windows")
async test "win32 console source preserves printable key modifiers" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  source.read_key_record(
    win32_test_key_record('a', control_key_state=Win32LeftAltPressed),
  )
  match source.try_get_event() {
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
      control_key_state=Win32ShiftPressed | Win32RightAltPressed,
    ),
  )
  match source.try_get_event() {
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
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '\u{1B}',
      virtual_key_code=0xdb,
      control_key_state=Win32LeftCtrlPressed,
    ),
  )
  match source.try_get_event() {
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
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  source.read_key_record(
    win32_test_key_record_charcode(
      0,
      virtual_key_code=0x20,
      control_key_state=Win32LeftCtrlPressed,
    ),
  )
  match source.try_get_event() {
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
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      source.read_key_record(
        win32_test_key_record(
          '@',
          control_key_state=Win32RightAltPressed | Win32LeftCtrlPressed,
        ),
      )
    }
    match source.read_decoded_input_event(50) {
      Input(Key(event)) =>
        @debug.assert_eq(
          event,
          @public_input.KeyEvent::new(Char('@'), text="@"),
        )
      _ => fail("expected decoded AltGr text key event")
    }
  }
}

///|
#cfg(platform="windows")
async test "win32 console source preserves keypad key metadata" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '1',
      virtual_key_code=0x61,
      control_key_state=Win32NumLockOn,
    ),
  )
  match source.try_get_event() {
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
  match source.try_get_event() {
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
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '\r',
      virtual_key_code=0x0d,
      control_key_state=Win32EnhancedKey,
    ),
  )
  match source.try_get_event() {
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
