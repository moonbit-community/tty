///|
const RecordKey : Int32 = 0x0001

///|
const RecordMouse : Int32 = 0x0002

///|
const RecordWindowBufferSize : Int32 = 0x0004

///|
const RecordFocus : Int32 = 0x0010

///|
const RightAltPressed : Int32 = 0x0001

///|
const LeftAltPressed : Int32 = 0x0002

///|
const RightCtrlPressed : Int32 = 0x0004

///|
const LeftCtrlPressed : Int32 = 0x0008

///|
const ShiftPressed : Int32 = 0x0010

///|
const MouseMoved : Int32 = 0x0001

///|
const MouseDoubleClick : Int32 = 0x0002

///|
const MouseWheeled : Int32 = 0x0004

///|
const MouseHorizontalWheeled : Int32 = 0x0008

///|
const MouseLeftButton : Int32 = 0x0001

///|
const MouseRightButton : Int32 = 0x0002

///|
const MouseMiddleButton : Int32 = 0x0004

///|
const MouseButtonMask : Int32 = 0x0007

///|
priv enum InputRecord {
  Key(KeyRecord)
  Mouse(MouseRecord)
  WindowBufferSize
  Focus(Bool)
  Unsupported
}

///|
priv struct KeyRecord {
  key_down : Int32
  repeat_count : Int32
  virtual_key_code : Int32
  virtual_scan_code : Int32
  unicode_char : Int32
  control_key_state : ControlKeyState
}

///|
priv struct MouseRecord {
  x : Int32
  y : Int32
  button_state : Int32
  control_key_state : ControlKeyState
  event_flags : Int32
}

///|
fn KeyRecord::new(
  key_down~ : Int32 = 1,
  repeat_count~ : Int32 = 1,
  virtual_key_code~ : Int32 = 0,
  virtual_scan_code~ : Int32 = 0,
  unicode_char~ : Int32 = 0,
  control_key_state~ : Int32 = 0,
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
fn MouseRecord::new(
  x~ : Int32 = 0,
  y~ : Int32 = 0,
  button_state~ : Int32 = 0,
  control_key_state~ : Int32 = 0,
  event_flags~ : Int32 = 0,
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
fn InputRecord::parse(record : Bytes) -> InputRecord {
  let bytes = record[:]
  guard u16_at(bytes, 0) is Some(event_type) else { return Unsupported }
  match event_type {
    RecordKey => parse_key_record(bytes)
    RecordMouse => parse_mouse_record(bytes)
    RecordWindowBufferSize => WindowBufferSize
    RecordFocus => parse_focus_record(bytes)
    _ => Unsupported
  }
}

///|
fn parse_key_record(bytes : BytesView) -> InputRecord {
  guard bool_at(bytes, 4) is Some(key_down) else { return Unsupported }
  guard u16_at(bytes, 8) is Some(repeat_count) else { return Unsupported }
  guard u16_at(bytes, 10) is Some(virtual_key_code) else { return Unsupported }
  guard u16_at(bytes, 12) is Some(virtual_scan_code) else { return Unsupported }
  guard u16_at(bytes, 14) is Some(unicode_char) else { return Unsupported }
  guard dword_at(bytes, 16) is Some(control_key_state) else {
    return Unsupported
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
  guard i16_at(bytes, 4) is Some(x) else { return Unsupported }
  guard i16_at(bytes, 6) is Some(y) else { return Unsupported }
  guard dword_at(bytes, 8) is Some(button_state) else { return Unsupported }
  guard dword_at(bytes, 12) is Some(control_key_state) else {
    return Unsupported
  }
  guard dword_at(bytes, 16) is Some(event_flags) else { return Unsupported }
  Mouse(
    MouseRecord::new(x~, y~, button_state~, control_key_state~, event_flags~),
  )
}

///|
fn parse_focus_record(bytes : BytesView) -> InputRecord {
  guard bool_at(bytes, 4) is Some(focus_set) else { return Unsupported }
  Focus(focus_set)
}

///|
fn bool_at(bytes : BytesView, offset : Int32) -> Bool? {
  dword_at(bytes, offset).map(value => value != 0)
}

///|
fn i16_at(bytes : BytesView, offset : Int32) -> Int32? {
  guard u16_at(bytes, offset) is Some(value) else { return None }
  if value >= 0x8000 {
    Some(value - 0x10000)
  } else {
    Some(value)
  }
}

///|
fn u16_at(bytes : BytesView, offset : Int32) -> Int32? {
  if offset < 0 || offset + 1 >= bytes.length() {
    return None
  }
  Some(bytes[offset].to_int() + bytes[offset + 1].to_int() * 0x100)
}

///|
fn dword_at(bytes : BytesView, offset : Int32) -> Int32? {
  guard u16_at(bytes, offset) is Some(low) else { return None }
  guard i16_at(bytes, offset + 2) is Some(high) else { return None }
  Some(low + high * 0x10000)
}
