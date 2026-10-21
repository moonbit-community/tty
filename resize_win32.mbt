///|
#cfg(platform="windows")
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int32,
) -> Event {
  self.read_decoded_event(esc_timeout_ms)
}
