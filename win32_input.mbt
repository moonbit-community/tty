///|
#cfg(platform="windows")
const Win32RecordKey : Int = 0x0001

///|
#cfg(platform="windows")
const Win32RecordWindowBufferSize : Int = 0x0004

///|
#cfg(platform="windows")
const Win32RecordFocus : Int = 0x0010

///|
#cfg(platform="windows")
const Win32RightAltPressed : Int = 0x0001

///|
#cfg(platform="windows")
const Win32LeftAltPressed : Int = 0x0002

///|
#cfg(platform="windows")
const Win32RightCtrlPressed : Int = 0x0004

///|
#cfg(platform="windows")
const Win32LeftCtrlPressed : Int = 0x0008

///|
#cfg(platform="windows")
const Win32ShiftPressed : Int = 0x0010

///|
#cfg(platform="windows")
const Win32NumLockOn : Int = 0x0020

///|
#cfg(platform="windows")
const Win32CapsLockOn : Int = 0x0080

///|
#cfg(platform="windows")
const Win32EnhancedKey : Int = 0x0100

///|
#cfg(platform="windows")
priv struct Win32InputRecord {
  event_type : Int
  key_down : Int
  repeat_count : Int
  virtual_key_code : Int
  unicode_char : Int
  control_key_state : Int
  focus_set : Int
}

///|
priv struct Win32ConsoleInputSource {
  input_fd : @async/types.Fd
  output_fd : @async/types.Fd
  byte_read : @async/io.PipeRead
  byte_write : @async/io.PipeWrite
  reader : @input.EventReader
  events : @aqueue.Queue[Event]
  pending_surrogate : Ref[Int]
}

///|
fn Win32ConsoleInputSource::new(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
) -> Win32ConsoleInputSource {
  let (byte_read, byte_write) = @async/io.pipe()
  {
    input_fd,
    output_fd,
    byte_read,
    byte_write,
    reader: @input.EventReader::new(byte_read as &@async/io.Reader),
    events: Queue(kind=Unbounded),
    pending_surrogate: Ref(0),
  }
}

///|
fn Win32ConsoleInputSource::close(self : Win32ConsoleInputSource) -> Unit {
  ignore(self.input_fd)
  ignore(self.output_fd)
  ignore(self.reader)
  ignore(self.pending_surrogate.val)
  self.byte_read.close()
  self.byte_write.close()
  self.events.close(clear=true)
}

///|
#cfg(platform="windows")
fn win32_console_input_source(
  input_fd : @async/types.Fd,
  output_fd : @async/types.Fd,
) -> Win32ConsoleInputSource? {
  if tty_isatty(input_fd) > 0 {
    Some(Win32ConsoleInputSource::new(input_fd, output_fd))
  } else {
    None
  }
}

///|
#cfg(not(platform="windows"))
fn win32_console_input_source(
  _input_fd : @async/types.Fd,
  _output_fd : @async/types.Fd,
) -> Win32ConsoleInputSource? {
  None
}

///|
#cfg(platform="windows")
async fn Tty::read_win32_console_event(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  match self.win32_console_input {
    Some(source) => source.read_event(esc_timeout_ms)
    None => self.read_decoded_input_event(esc_timeout_ms)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  match self.win32_console_input {
    Some(source) =>
      @async.with_task_group() <| group => {
        group.spawn_bg(no_wait=true) <| () => { source.read_records() }
        source.read_internal_event(esc_timeout_ms)
      }
    None => self.reader.read_event(esc_timeout_ms~)
  }
}

///|
#cfg(not(platform="windows"))
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_event(
  self : Win32ConsoleInputSource,
  esc_timeout_ms : Int,
) -> Event {
  match self.try_get_event() {
    Some(event) => return event
    None => ()
  }
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.read_records() }
    group.spawn_bg(no_wait=true) <| () => {
      group.return_immediately(self.read_decoded_input_event(esc_timeout_ms))
    }
    self.events.get()
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_decoded_input_event(
  self : Win32ConsoleInputSource,
  esc_timeout_ms : Int,
) -> Event {
  for ;; {
    match self.read_internal_event(esc_timeout_ms) {
      Input(event) => return Input(event)
      CursorPosition(..) => ()
      KeyboardEnhancementFlags(_) => ()
      PrimaryDeviceAttributes(_) => ()
      DynamicColor(..) => ()
    }
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_internal_event(
  self : Win32ConsoleInputSource,
  esc_timeout_ms : Int,
) -> @input.Event {
  self.reader.read_event(esc_timeout_ms~)
}

///|
#cfg(platform="windows")
fn Win32ConsoleInputSource::try_get_event(
  self : Win32ConsoleInputSource,
) -> Event? {
  try self.events.try_get() catch {
    _ => None
  } noraise {
    event => event
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_records(
  self : Win32ConsoleInputSource,
) -> Unit {
  for ;; {
    match win32_read_console_input_record(self.input_fd) {
      None => @async.sleep(10)
      Some(record) => self.read_record(record)
    }
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_record(
  self : Win32ConsoleInputSource,
  record : Win32InputRecord,
) -> Unit {
  match record.event_type {
    Win32RecordKey => self.read_key_record(record)
    Win32RecordWindowBufferSize => {
      self.pending_surrogate.val = 0
      match self.window_size() {
        Some(size) => self.events.put(Resize(size))
        None => ()
      }
    }
    Win32RecordFocus => {
      self.pending_surrogate.val = 0
      if record.focus_set != 0 {
        self.events.put(Input(FocusIn))
      } else {
        self.events.put(Input(FocusOut))
      }
    }
    _ => {
      self.pending_surrogate.val = 0
      ()
    }
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::read_key_record(
  self : Win32ConsoleInputSource,
  record : Win32InputRecord,
) -> Unit {
  if record.key_down == 0 {
    return
  }
  if !record.win32_key_text_uses_decoder() {
    return self.queue_key_input(record)
  }
  match record.win32_key_text(self.pending_surrogate) {
    Some(text) =>
      for _ in 0..<record.win32_repeat_count() {
        self.byte_write.write(text)
      }
    None => self.queue_key_input(record)
  }
}

///|
#cfg(platform="windows")
async fn Win32ConsoleInputSource::queue_key_input(
  self : Win32ConsoleInputSource,
  record : Win32InputRecord,
) -> Unit {
  match record.win32_key_input(self.pending_surrogate) {
    Some(input) =>
      for _ in 0..<record.win32_repeat_count() {
        self.events.put(Input(input))
      }
    None => ()
  }
}

///|
#cfg(platform="windows")
fn Win32ConsoleInputSource::window_size(
  self : Win32ConsoleInputSource,
) -> WindowSize? {
  let rows = Ref(0)
  let cols = Ref(0)
  if tty_get_window_size(self.output_fd, rows, cols) < 0 {
    None
  } else {
    Some({ rows: rows.val, cols: cols.val })
  }
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_repeat_count(self : Win32InputRecord) -> Int {
  if self.repeat_count > 0 {
    self.repeat_count
  } else {
    1
  }
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_text_uses_decoder(
  self : Win32InputRecord,
) -> Bool {
  self.key_down != 0 && !self.win32_has_direct_key_metadata()
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_has_direct_key_metadata(
  self : Win32InputRecord,
) -> Bool {
  (self.win32_has_keyboard_modifier() && !self.win32_is_alt_gr_text()) ||
  self.win32_is_keypad()
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_has_keyboard_modifier(
  self : Win32InputRecord,
) -> Bool {
  win32_has_state(
    self.control_key_state,
    Win32ShiftPressed |
    Win32LeftAltPressed |
    Win32RightAltPressed |
    Win32LeftCtrlPressed |
    Win32RightCtrlPressed,
  )
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_is_alt_gr_text(self : Win32InputRecord) -> Bool {
  let alt_gr_state = Win32RightAltPressed | Win32LeftCtrlPressed
  self.key_down != 0 &&
  self.unicode_char > 0x1f &&
  (self.control_key_state & alt_gr_state) == alt_gr_state &&
  !win32_has_state(
    self.control_key_state,
    Win32LeftAltPressed | Win32RightCtrlPressed,
  )
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_text(
  self : Win32InputRecord,
  pending_surrogate : Ref[Int],
) -> String? {
  if self.key_down == 0 {
    return None
  }
  let charcode = self.unicode_char
  if charcode == 0 {
    pending_surrogate.val = 0
    return None
  }
  if win32_is_high_surrogate(charcode) {
    pending_surrogate.val = charcode
    return None
  }
  if win32_is_low_surrogate(charcode) {
    let high = pending_surrogate.val
    pending_surrogate.val = 0
    guard high != 0 else { return None }
    let char = win32_decode_surrogate_pair(high, charcode)
    return Some([char])
  }
  pending_surrogate.val = 0
  Some([charcode.unsafe_to_char()])
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_input(
  self : Win32InputRecord,
  pending_surrogate : Ref[Int],
) -> @public_input.InputEvent? {
  guard self.win32_key_event(pending_surrogate) is Some(event) else {
    return None
  }
  Some(Key(event))
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_kind(
  self : Win32InputRecord,
) -> @public_input.KeyEventKind {
  if self.key_down == 0 {
    Release
  } else if self.repeat_count > 1 {
    Repeat
  } else {
    Press
  }
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_modifiers(
  self : Win32InputRecord,
) -> @public_input.KeyModifiers {
  @public_input.KeyModifiers::new(
    shift=win32_has_state(self.control_key_state, Win32ShiftPressed),
    alt=win32_has_state(
      self.control_key_state,
      Win32LeftAltPressed | Win32RightAltPressed,
    ),
    ctrl=win32_has_state(
      self.control_key_state,
      Win32LeftCtrlPressed | Win32RightCtrlPressed,
    ),
  )
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_state(
  self : Win32InputRecord,
) -> @public_input.KeyEventState {
  @public_input.KeyEventState::new(
    keypad=self.win32_is_keypad(),
    caps_lock=win32_has_state(self.control_key_state, Win32CapsLockOn),
    num_lock=win32_has_state(self.control_key_state, Win32NumLockOn),
  )
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_event(
  self : Win32InputRecord,
  pending_surrogate : Ref[Int],
) -> @public_input.KeyEvent? {
  let kind = self.win32_key_kind()
  let modifiers = self.win32_modifiers()
  let state = self.win32_key_state()
  match self.win32_key_code_from_virtual_key() {
    Some(code) => {
      pending_surrogate.val = 0
      return Some(@public_input.KeyEvent::new(code, modifiers~, kind~, state~))
    }
    None => ()
  }
  let charcode = self.unicode_char
  if charcode == 0 {
    pending_surrogate.val = 0
    return win32_control_code_from_virtual_key(self.virtual_key_code).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if charcode >= 0x00 && charcode <= 0x1f {
    pending_surrogate.val = 0
    return win32_control_code_from_char(charcode).map(code => {
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
    })
  }
  if win32_is_high_surrogate(charcode) {
    pending_surrogate.val = charcode
    return None
  }
  if win32_is_low_surrogate(charcode) {
    let high = pending_surrogate.val
    pending_surrogate.val = 0
    guard high != 0 else { return None }
    let char = win32_decode_surrogate_pair(high, charcode)
    return Some(self.win32_char_key_event(char, modifiers, kind, state))
  }
  pending_surrogate.val = 0
  let char = charcode.unsafe_to_char()
  Some(self.win32_char_key_event(char, modifiers, kind, state))
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_key_code_from_virtual_key(
  self : Win32InputRecord,
) -> @public_input.KeyCode? {
  if self.win32_is_keypad_enter() {
    Some(KeypadEnter)
  } else {
    win32_key_code_from_virtual_key(self.virtual_key_code)
  }
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_is_keypad(self : Win32InputRecord) -> Bool {
  win32_virtual_key_is_keypad(self.virtual_key_code) ||
  self.win32_is_keypad_enter() ||
  self.win32_is_keypad_navigation()
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_is_keypad_enter(self : Win32InputRecord) -> Bool {
  self.virtual_key_code == 0x0d &&
  win32_has_state(self.control_key_state, Win32EnhancedKey)
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_is_keypad_navigation(
  self : Win32InputRecord,
) -> Bool {
  win32_virtual_key_is_navigation(self.virtual_key_code) &&
  !win32_has_state(self.control_key_state, Win32EnhancedKey)
}

///|
#cfg(platform="windows")
fn Win32InputRecord::win32_char_key_event(
  self : Win32InputRecord,
  char : Char,
  modifiers : @public_input.KeyModifiers,
  kind : @public_input.KeyEventKind,
  state : @public_input.KeyEventState,
) -> @public_input.KeyEvent {
  match win32_text_for_key(self, char) {
    Some(text) =>
      @public_input.KeyEvent::new(Char(char), modifiers~, kind~, state~, text~)
    None => @public_input.KeyEvent::new(Char(char), modifiers~, kind~, state~)
  }
}

///|
#cfg(platform="windows")
fn win32_text_for_key(record : Win32InputRecord, char : Char) -> String? {
  if record.key_down == 0 {
    None
  } else {
    Some([char])
  }
}

///|
#cfg(platform="windows")
fn win32_key_code_from_virtual_key(vk : Int) -> @public_input.KeyCode? {
  if vk >= 0x70 && vk <= 0x87 {
    return win32_function_key(vk - 0x6f)
  }
  match vk {
    0x08 => Some(Backspace)
    0x09 => Some(Tab)
    0x0d => Some(Enter)
    0x13 => Some(Pause)
    0x1b => Some(Escape)
    0x21 => Some(PageUp)
    0x22 => Some(PageDown)
    0x23 => Some(End)
    0x24 => Some(Home)
    0x25 => Some(Left)
    0x26 => Some(Up)
    0x27 => Some(Right)
    0x28 => Some(Down)
    0x2c => Some(PrintScreen)
    0x2d => Some(Insert)
    0x2e => Some(Delete)
    0x5d => Some(Menu)
    0x6a => Some(KeypadMultiply)
    0x6b => Some(KeypadPlus)
    0x6c => Some(KeypadSeparator)
    0x6d => Some(KeypadMinus)
    0x6e => Some(KeypadDecimal)
    0x6f => Some(KeypadDivide)
    0x90 => Some(NumLock)
    0x91 => Some(ScrollLock)
    _ =>
      if vk >= 0x60 && vk <= 0x69 {
        win32_keypad_digit(vk - 0x60)
      } else {
        None
      }
  }
}

///|
#cfg(platform="windows")
fn win32_control_code_from_char(charcode : Int) -> @public_input.KeyCode? {
  match charcode {
    0x00 => Some(Char(' '))
    0x01..=0x1a => Some(Char((charcode - 1 + 'a'.to_int()).unsafe_to_char()))
    0x1b => Some(Escape)
    0x1c..=0x1f => Some(Char((charcode - 0x1c + '4'.to_int()).unsafe_to_char()))
    _ => None
  }
}

///|
#cfg(platform="windows")
fn win32_control_code_from_virtual_key(vk : Int) -> @public_input.KeyCode? {
  if vk == 0x20 {
    Some(Char(' '))
  } else if vk >= 0x41 && vk <= 0x5a {
    Some(Char((vk - 0x41 + 'a'.to_int()).unsafe_to_char()))
  } else {
    None
  }
}

///|
#cfg(platform="windows")
fn win32_function_key(number : Int) -> @public_input.KeyCode? {
  match number {
    1 => Some(F1)
    2 => Some(F2)
    3 => Some(F3)
    4 => Some(F4)
    5 => Some(F5)
    6 => Some(F6)
    7 => Some(F7)
    8 => Some(F8)
    9 => Some(F9)
    10 => Some(F10)
    11 => Some(F11)
    12 => Some(F12)
    13 => Some(F13)
    14 => Some(F14)
    15 => Some(F15)
    16 => Some(F16)
    17 => Some(F17)
    18 => Some(F18)
    19 => Some(F19)
    20 => Some(F20)
    21 => Some(F21)
    22 => Some(F22)
    23 => Some(F23)
    24 => Some(F24)
    _ => None
  }
}

///|
#cfg(platform="windows")
fn win32_keypad_digit(number : Int) -> @public_input.KeyCode? {
  match number {
    0 => Some(Keypad0)
    1 => Some(Keypad1)
    2 => Some(Keypad2)
    3 => Some(Keypad3)
    4 => Some(Keypad4)
    5 => Some(Keypad5)
    6 => Some(Keypad6)
    7 => Some(Keypad7)
    8 => Some(Keypad8)
    9 => Some(Keypad9)
    _ => None
  }
}

///|
#cfg(platform="windows")
fn win32_virtual_key_is_keypad(vk : Int) -> Bool {
  vk >= 0x60 && vk <= 0x6f
}

///|
#cfg(platform="windows")
fn win32_virtual_key_is_navigation(vk : Int) -> Bool {
  match vk {
    0x21 | 0x22 | 0x23 | 0x24 | 0x25 | 0x26 | 0x27 | 0x28 | 0x2d | 0x2e => true
    _ => false
  }
}

///|
#cfg(platform="windows")
fn win32_has_state(state : Int, mask : Int) -> Bool {
  (state & mask) != 0
}

///|
#cfg(platform="windows")
fn win32_is_high_surrogate(code : Int) -> Bool {
  code >= 0xd800 && code <= 0xdbff
}

///|
#cfg(platform="windows")
fn win32_is_low_surrogate(code : Int) -> Bool {
  code >= 0xdc00 && code <= 0xdfff
}

///|
#cfg(platform="windows")
fn win32_decode_surrogate_pair(high : Int, low : Int) -> Char {
  let code = 0x10000 + (high - 0xd800) * 0x400 + (low - 0xdc00)
  code.unsafe_to_char()
}

///|
#borrow(event_type, key_down, repeat_count, virtual_key_code, unicode_char, control_key_state, focus_set)
#cfg(platform="windows")
extern "c" fn win32_read_console_input_record_ffi(
  fd : @async/types.Fd,
  event_type : Ref[Int],
  key_down : Ref[Int],
  repeat_count : Ref[Int],
  virtual_key_code : Ref[Int],
  unicode_char : Ref[Int],
  control_key_state : Ref[Int],
  focus_set : Ref[Int],
) -> Int = "moonbit_tty_read_console_input_record"

///|
#cfg(platform="windows")
fn win32_read_console_input_record(
  fd : @async/types.Fd,
) -> Win32InputRecord? raise {
  let event_type = Ref(0)
  let key_down = Ref(0)
  let repeat_count = Ref(0)
  let virtual_key_code = Ref(0)
  let unicode_char = Ref(0)
  let control_key_state = Ref(0)
  let focus_set = Ref(0)
  let rc = win32_read_console_input_record_ffi(
    fd, event_type, key_down, repeat_count, virtual_key_code, unicode_char, control_key_state,
    focus_set,
  )
  if rc < 0 {
    @os_error.check_errno("ReadConsoleInputW")
  }
  if rc == 0 {
    None
  } else {
    Some({
      event_type: event_type.val,
      key_down: key_down.val,
      repeat_count: repeat_count.val,
      virtual_key_code: virtual_key_code.val,
      unicode_char: unicode_char.val,
      control_key_state: control_key_state.val,
      focus_set: focus_set.val,
    })
  }
}
