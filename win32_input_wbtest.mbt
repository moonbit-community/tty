///|
#cfg(platform="windows")
fn win32_test_key_record(
  char : Char,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> Win32KeyRecord {
  {
    key_down,
    repeat_count: 1,
    virtual_key_code,
    virtual_scan_code: 0,
    unicode_char: char.to_int(),
    control_key_state,
  }
}

///|
#cfg(platform="windows")
fn win32_test_key_record_charcode(
  charcode : Int,
  virtual_key_code? : Int = 0,
  control_key_state? : Int = 0,
  key_down? : Int = 1,
) -> Win32KeyRecord {
  {
    key_down,
    repeat_count: 1,
    virtual_key_code,
    virtual_scan_code: 0,
    unicode_char: charcode,
    control_key_state,
  }
}

///|
#cfg(platform="windows")
fn win32_test_mouse_record(
  x? : Int = 0,
  y? : Int = 0,
  button_state? : Int = 0,
  control_key_state? : Int = 0,
  event_flags? : Int = 0,
) -> Win32MouseRecord {
  { x, y, button_state, control_key_state, event_flags }
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
fn win32_test_raw_record(event_type : Int) -> FixedArray[Byte] {
  let buf = FixedArray::make(sizeof_win32_input_record, b'\x00')
  win32_test_set_u16_le(buf, 0, event_type)
  buf
}

///|
#cfg(platform="windows")
fn win32_test_raw_input_record(buf : FixedArray[Byte]) -> Win32RawInputRecord {
  Win32RawInputRecord(buf.unsafe_reinterpret_as_bytes())
}

///|
#cfg(platform="windows")
fn win32_test_set_u16_le(
  buf : FixedArray[Byte],
  offset : Int,
  value : Int,
) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
}

///|
#cfg(platform="windows")
fn win32_test_set_u32_le(
  buf : FixedArray[Byte],
  offset : Int,
  value : Int,
) -> Unit {
  buf[offset] = (value & 0xff).to_byte()
  buf[offset + 1] = ((value / 0x100) & 0xff).to_byte()
  buf[offset + 2] = ((value / 0x10000) & 0xff).to_byte()
  buf[offset + 3] = ((value / 0x1000000) & 0xff).to_byte()
}

///|
#cfg(platform="windows")
test "win32 raw input record parses key records" {
  let buf = win32_test_raw_record(Win32RecordKey)
  win32_test_set_u32_le(buf, 4, 1)
  win32_test_set_u16_le(buf, 8, 2)
  win32_test_set_u16_le(buf, 10, 0x41)
  win32_test_set_u16_le(buf, 12, 0x1e)
  win32_test_set_u16_le(buf, 14, 'A'.to_int())
  win32_test_set_u32_le(buf, 16, Win32ShiftPressed)
  match win32_test_raw_input_record(buf).parse() {
    Key(record) => {
      @debug.assert_eq(record.key_down, 1)
      @debug.assert_eq(record.repeat_count, 2)
      @debug.assert_eq(record.virtual_key_code, 0x41)
      @debug.assert_eq(record.virtual_scan_code, 0x1e)
      @debug.assert_eq(record.unicode_char, 'A'.to_int())
      @debug.assert_eq(record.control_key_state, Win32ShiftPressed)
    }
    _ => fail("expected key record")
  }
}

///|
#cfg(platform="windows")
test "win32 raw input record parses mouse records" {
  let buf = win32_test_raw_record(Win32RecordMouse)
  win32_test_set_u16_le(buf, 4, 30)
  win32_test_set_u16_le(buf, 6, 2)
  win32_test_set_u32_le(buf, 8, Win32MouseLeftButton)
  win32_test_set_u32_le(buf, 12, Win32ShiftPressed)
  win32_test_set_u32_le(buf, 16, Win32MouseMoved)
  match win32_test_raw_input_record(buf).parse() {
    Mouse(record) => {
      @debug.assert_eq(record.x, 30)
      @debug.assert_eq(record.y, 2)
      @debug.assert_eq(record.button_state, Win32MouseLeftButton)
      @debug.assert_eq(record.control_key_state, Win32ShiftPressed)
      @debug.assert_eq(record.event_flags, Win32MouseMoved)
    }
    _ => fail("expected mouse record")
  }
}

///|
#cfg(platform="windows")
test "win32 raw input record parses focus records" {
  let buf = win32_test_raw_record(Win32RecordFocus)
  win32_test_set_u32_le(buf, 4, 1)
  match win32_test_raw_input_record(buf).parse() {
    Focus(true) => ()
    _ => fail("expected focus record")
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
async test "win32 console source preserves native events during internal reads" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      source.read_record(Focus(true))
      for char in "\u{1B}[7;9R" {
        source.read_key_record(win32_test_key_record(char))
      }
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
}

///|
#cfg(platform="windows")
async test "win32 console source maps native mouse records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, event_flags=Win32MouseMoved),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Mouse(event))) =>
      @debug.assert_eq(event, @public_input.MouseEvent::new(Move, 3, 31))
    _ => fail("expected mouse move event")
  }
  source.read_mouse_record(
    win32_test_mouse_record(x=30, y=2, button_state=Win32MouseLeftButton),
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
      button_state=Win32MouseLeftButton,
      control_key_state=Win32ShiftPressed,
      event_flags=Win32MouseMoved,
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
      event_flags=Win32MouseWheeled,
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
    win32_test_key_record('a', control_key_state=Win32LeftAltPressed),
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
      control_key_state=Win32ShiftPressed | Win32RightAltPressed,
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
      control_key_state=Win32LeftCtrlPressed,
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
      control_key_state=Win32LeftCtrlPressed,
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
  let source = win32_test_console_tty(dummy_input, dummy_output)
  defer source.close()
  source.read_key_record(
    win32_test_key_record(
      '1',
      virtual_key_code=0x61,
      control_key_state=Win32NumLockOn,
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
      control_key_state=Win32EnhancedKey,
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
      control_key_state=Win32EnhancedKey,
    ),
  )
  match win32_test_try_get_event(source) {
    Some(Input(Key(event))) =>
      @debug.assert_eq(event, @public_input.KeyEvent::new(End))
    _ => fail("expected enhanced End key event")
  }
}
