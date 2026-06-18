///|
const SixelGraphicsCapability : Int = 4

///|
const Vt220DeviceAttribute : Int = 62

///|
/// Query whether the terminal reports Sixel graphics support in Primary DA.
///
/// User input received while waiting for terminal responses is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_sixel_graphics_support(
  self : Self,
  timeout_ms? : Int = 100,
) -> Bool {
  match
    @async.with_timeout_opt(timeout_ms, () => {
      self.write(@vt.request_primary_device_attributes)
      for ;; {
        match self.read_internal_event() {
          PrimaryDeviceAttributes(attributes) =>
            return primary_device_attributes_support_sixel(attributes)
          CursorPosition(..) => ()
          KeyboardEnhancementFlags(_) => ()
          DynamicColor(..) => ()
          KittyGraphicsResponse(..) => ()
          Input(event) => self.pending_input.push(event)
        }
      }
    }) {
    Some(supported) => supported
    None => false
  }
}

///|
/// Display a complete Sixel DCS byte stream at the current cursor.
///
/// The root package treats Sixel as terminal transport. Image conversion and
/// Sixel encoding are left to callers or demos.
pub async fn Tty::display_sixel(self : Self, sixel : BytesView) -> Unit {
  self.write(sixel)
}

///|
fn primary_device_attributes_support_sixel(attributes : BytesView) -> Bool {
  match attributes {
    [b'\x1b', b'[', b'?', .. body, b'c'] =>
      primary_da_parameters_support_sixel(body)
    [b'\x9b', b'?', .. body, b'c'] => primary_da_parameters_support_sixel(body)
    _ => false
  }
}

///|
fn primary_da_parameters_support_sixel(params : BytesView) -> Bool {
  let mut index = 0
  let mut value = 0
  let mut has_digit = false
  let mut vt220_or_newer = false
  let mut sixel = false
  for byte in params {
    match byte {
      b'0'..=b'9' => {
        has_digit = true
        value = value * 10 + byte.to_int() - b'0'.to_int()
      }
      b';' => {
        if has_digit {
          if index == 0 {
            vt220_or_newer = value >= Vt220DeviceAttribute
          } else if value == SixelGraphicsCapability {
            sixel = true
          }
        }
        index += 1
        value = 0
        has_digit = false
      }
      _ => return false
    }
  }
  if has_digit {
    if index == 0 {
      vt220_or_newer = value >= Vt220DeviceAttribute
    } else if value == SixelGraphicsCapability {
      sixel = true
    }
  }
  vt220_or_newer && sixel
}
