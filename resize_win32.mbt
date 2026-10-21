///|
/// Read the next root event from a redirected (non-console) input handle.
///
/// Such handles carry no console resize records, so there is no resize source.
#cfg(platform="windows")
async fn Tty::read_byte_stream_event(
  self : Self,
  esc_timeout_ms : Int32,
) -> Event {
  read_decoded_input_event(self.reader, esc_timeout_ms)
}
