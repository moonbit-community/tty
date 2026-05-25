///|
/// Terminal stream event decoded from the input byte stream.
///
/// Terminal replies are part of the byte stream and may be interleaved with
/// user input.
pub(all) enum Event {
  Input(@public_input.InputEvent)
  CursorPosition(row~ : Int, col~ : Int)
  KeyboardEnhancementFlags(Int)
  PrimaryDeviceAttributes(Bytes)
} derive(Eq, Debug)
