///|
#cfg(platform="windows")
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  self.read_decoded_input_event(esc_timeout_ms)
}
