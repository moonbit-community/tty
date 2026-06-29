///|
pub const RecordKey : Int = 0x0001

///|
pub const RecordMouse : Int = 0x0002

///|
pub const RecordWindowBufferSize : Int = 0x0004

///|
pub const RecordFocus : Int = 0x0010

///|
pub const RightAltPressed : Int = 0x0001

///|
pub const LeftAltPressed : Int = 0x0002

///|
pub const RightCtrlPressed : Int = 0x0004

///|
pub const LeftCtrlPressed : Int = 0x0008

///|
pub const ShiftPressed : Int = 0x0010

///|
pub const NumLockOn : Int = 0x0020

///|
pub const CapsLockOn : Int = 0x0080

///|
pub const EnhancedKey : Int = 0x0100

///|
pub const MouseMoved : Int = 0x0001

///|
pub const MouseDoubleClick : Int = 0x0002

///|
pub const MouseWheeled : Int = 0x0004

///|
pub const MouseHorizontalWheeled : Int = 0x0008

///|
pub const MouseLeftButton : Int = 0x0001

///|
pub const MouseRightButton : Int = 0x0002

///|
pub const MouseMiddleButton : Int = 0x0004

///|
const MouseButtonMask : Int = 0x0007

///|
pub(all) enum InputRecord {
  Key(KeyRecord)
  Mouse(MouseRecord)
  WindowBufferSize(Coord)
  Focus(Bool)
  Unsupported(Int)
}

///|
pub struct Coord {
  x : Int
  y : Int
}

///|
pub struct KeyRecord {
  key_down : Int
  repeat_count : Int
  virtual_key_code : Int
  virtual_scan_code : Int
  unicode_char : Int
  control_key_state : ControlKeyState
}

///|
pub struct MouseRecord {
  x : Int
  y : Int
  button_state : Int
  control_key_state : ControlKeyState
  event_flags : Int
}

///|
pub struct MouseButtonState {
  mut buttons : Int
}

///|
pub fn KeyRecord::new(
  key_down? : Int = 1,
  repeat_count? : Int = 1,
  virtual_key_code? : Int = 0,
  virtual_scan_code? : Int = 0,
  unicode_char? : Int = 0,
  control_key_state? : Int = 0,
) -> KeyRecord {
  {
    key_down,
    repeat_count,
    virtual_key_code,
    virtual_scan_code,
    unicode_char,
    control_key_state: ControlKeyState(control_key_state),
  }
}

///|
pub fn MouseRecord::new(
  x? : Int = 0,
  y? : Int = 0,
  button_state? : Int = 0,
  control_key_state? : Int = 0,
  event_flags? : Int = 0,
) -> MouseRecord {
  {
    x,
    y,
    button_state,
    control_key_state: ControlKeyState(control_key_state),
    event_flags,
  }
}

///|
pub fn MouseButtonState::new() -> MouseButtonState {
  { buttons: 0 }
}

///|
pub fn InputRecord::parse(record : Bytes) -> InputRecord {
  let bytes = record[:]
  guard u16_at(bytes, 0) is Some(event_type) else { return Unsupported(0) }
  match event_type {
    RecordKey => parse_key_record(bytes)
    RecordMouse => parse_mouse_record(bytes)
    RecordWindowBufferSize => parse_window_buffer_size_record(bytes)
    RecordFocus => parse_focus_record(bytes)
    _ => Unsupported(event_type)
  }
}

///|
fn parse_key_record(bytes : BytesView) -> InputRecord {
  guard bool_at(bytes, 4) is Some(key_down) else {
    return Unsupported(RecordKey)
  }
  guard u16_at(bytes, 8) is Some(repeat_count) else {
    return Unsupported(RecordKey)
  }
  guard u16_at(bytes, 10) is Some(virtual_key_code) else {
    return Unsupported(RecordKey)
  }
  guard u16_at(bytes, 12) is Some(virtual_scan_code) else {
    return Unsupported(RecordKey)
  }
  guard u16_at(bytes, 14) is Some(unicode_char) else {
    return Unsupported(RecordKey)
  }
  guard dword_at(bytes, 16) is Some(control_key_state) else {
    return Unsupported(RecordKey)
  }
  Key(
    KeyRecord::new(
      key_down=if key_down { 1 } else { 0 },
      repeat_count~,
      virtual_key_code~,
      virtual_scan_code~,
      unicode_char~,
      control_key_state~,
    ),
  )
}

///|
fn parse_mouse_record(bytes : BytesView) -> InputRecord {
  guard i16_at(bytes, 4) is Some(x) else { return Unsupported(RecordMouse) }
  guard i16_at(bytes, 6) is Some(y) else { return Unsupported(RecordMouse) }
  guard dword_at(bytes, 8) is Some(button_state) else {
    return Unsupported(RecordMouse)
  }
  guard dword_at(bytes, 12) is Some(control_key_state) else {
    return Unsupported(RecordMouse)
  }
  guard dword_at(bytes, 16) is Some(event_flags) else {
    return Unsupported(RecordMouse)
  }
  Mouse(
    MouseRecord::new(x~, y~, button_state~, control_key_state~, event_flags~),
  )
}

///|
fn parse_window_buffer_size_record(bytes : BytesView) -> InputRecord {
  guard i16_at(bytes, 4) is Some(x) else {
    return Unsupported(RecordWindowBufferSize)
  }
  guard i16_at(bytes, 6) is Some(y) else {
    return Unsupported(RecordWindowBufferSize)
  }
  WindowBufferSize({ x, y })
}

///|
fn parse_focus_record(bytes : BytesView) -> InputRecord {
  guard bool_at(bytes, 4) is Some(focus_set) else {
    return Unsupported(RecordFocus)
  }
  Focus(focus_set)
}

///|
fn bool_at(bytes : BytesView, offset : Int) -> Bool? {
  dword_at(bytes, offset).map(value => value != 0)
}

///|
fn i16_at(bytes : BytesView, offset : Int) -> Int? {
  guard u16_at(bytes, offset) is Some(value) else { return None }
  if value >= 0x8000 {
    Some(value - 0x10000)
  } else {
    Some(value)
  }
}

///|
fn u16_at(bytes : BytesView, offset : Int) -> Int? {
  if offset < 0 || offset + 1 >= bytes.length() {
    return None
  }
  Some(bytes[offset].to_int() + bytes[offset + 1].to_int() * 0x100)
}

///|
fn dword_at(bytes : BytesView, offset : Int) -> Int? {
  guard u16_at(bytes, offset) is Some(low) else { return None }
  guard i16_at(bytes, offset + 2) is Some(high) else { return None }
  Some(low + high * 0x10000)
}
