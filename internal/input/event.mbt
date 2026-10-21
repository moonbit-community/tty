///|
/// Terminal stream event decoded from the input byte stream.
///
/// Terminal replies are part of the byte stream and may be interleaved with
/// user input.
pub(all) enum Event {
  Input(@public_input.InputEvent)
  CursorPosition(row~ : Int32, col~ : Int32)
  KeyboardEnhancementFlags(Int32)
  PrimaryDeviceAttributes(Bytes)
  DynamicColor(code~ : Int32, red~ : Int32, green~ : Int32, blue~ : Int32)
} derive(Eq, Debug)

///|
pub extend Event with Eq::{equal, not_equal}

///|
pub extend Event with @debug.Debug::{to_repr}
