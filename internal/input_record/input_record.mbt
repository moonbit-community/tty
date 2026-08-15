///|
pub enum InputRecord {
  KeyEvent(KeyEventRecord)
  MouseEvent(MouseEventRecord)
  WindowBufferSizeEvent(WindowBufferSizeEventRecord)
  MenuEvent(MenuEventRecord)
  FocusEvent(FocusEventRecord)
}

///|
const KEY_EVENT : UInt = 0x0001

///|
const MOUSE_EVENT : UInt = 0x0002

///|
const WINDOW_BUFFER_SIZE_EVENT : UInt = 0x0004

///|
const MENU_EVENT : UInt = 0x0008

///|
const FOCUS_EVENT : UInt = 0x0010

///|
pub struct FocusEventRecord {
  set_focus : Bool
}

///|
fn FocusEventRecord::parse(
  bytes : BytesView,
) -> FocusEventRecord raise InvalidInputRecord {
  guard bytes is [i32le(bSetFocus), ..] else { raise InvalidPayload(bytes) }
  { set_focus: bSetFocus != 0 }
}

///|
pub struct KeyEventRecord {
  key_down : Bool
  repeat_count : UInt16
  virtual_key_code : UInt16
  virtual_scan_code : UInt16
  unicode_char : UInt16
  control_key_state : UInt
}

///|
pub fn KeyEventRecord::parse(
  bytes : BytesView,
) -> KeyEventRecord raise InvalidInputRecord {
  guard bytes
    is [
      i32le(key_down),
      u16le(repeat_count),
      u16le(virtual_key_code),
      u16le(virtual_scan_code),
      u16le(unicode_char),
      u32le(control_key_state),
      ..,
    ] else {
    raise InvalidPayload(bytes)
  }
  {
    key_down: key_down != 0,
    repeat_count: repeat_count.to_uint16(),
    virtual_key_code: virtual_key_code.to_uint16(),
    virtual_scan_code: virtual_scan_code.to_uint16(),
    unicode_char: unicode_char.to_uint16(),
    control_key_state,
  }
}

///|
pub struct Coord {
  x : UInt16
  y : UInt16
}

///|
pub struct MouseEventRecord {
  mouse_position : Coord
  button_state : UInt
  control_key_state : UInt
  event_flags : UInt
}

///|
fn MouseEventRecord::parse(
  bytes : BytesView,
) -> MouseEventRecord raise InvalidInputRecord {
  guard bytes
    is [
      u16le(pos_x),
      u16le(pos_y),
      u32le(button_state),
      u32le(control_key_state),
      u32le(event_flags),
      ..,
    ] else {
    raise InvalidPayload(bytes)
  }
  {
    mouse_position: { x: pos_x.to_uint16(), y: pos_y.to_uint16() },
    button_state,
    control_key_state,
    event_flags,
  }
}

///|
pub struct WindowBufferSizeEventRecord {
  size : Coord
}

///|
fn WindowBufferSizeEventRecord::parse(
  bytes : BytesView,
) -> WindowBufferSizeEventRecord raise InvalidInputRecord {
  guard bytes is [u16le(size_x), u16le(size_y), ..] else {
    raise InvalidPayload(bytes)
  }
  { size: { x: size_x.to_uint16(), y: size_y.to_uint16() } }
}

///|
pub struct MenuEventRecord {
  command_id : UInt
}

///|
fn MenuEventRecord::parse(
  bytes : BytesView,
) -> MenuEventRecord raise InvalidInputRecord {
  guard bytes is [u32le(command_id), ..] else { raise InvalidPayload(bytes) }
  { command_id, }
}

///|
suberror InvalidInputRecord {
  UnrecognizedEventType(UInt16)
  InvalidPayload(BytesView)
}

///|
pub fn InputRecord::parse(
  bytes : BytesView,
) -> InputRecord raise InvalidInputRecord {
  match bytes {
    [u16le(KEY_EVENT), u16le(_), .. key_event_record] =>
      KeyEvent(KeyEventRecord::parse(key_event_record))
    [u16le(MOUSE_EVENT), u16le(_), .. mouse_event_record] =>
      MouseEvent(MouseEventRecord::parse(mouse_event_record))
    [
      u16le(WINDOW_BUFFER_SIZE_EVENT),
      u16le(_),
      .. window_buffer_size_event_record,
    ] =>
      WindowBufferSizeEvent(
        WindowBufferSizeEventRecord::parse(window_buffer_size_event_record),
      )
    [u16le(FOCUS_EVENT), u16le(_), .. focus_event_record] =>
      FocusEvent(FocusEventRecord::parse(focus_event_record))
    [u16le(MENU_EVENT), u16le(_), .. menu_event_record] =>
      MenuEvent(MenuEventRecord::parse(menu_event_record))
    [u16le(event_type), ..] =>
      raise UnrecognizedEventType(event_type.to_uint16())
    _ => raise InvalidPayload(bytes)
  }
}
