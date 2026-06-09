///|
#cfg(platform="windows")
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  self.read_win32_console_event(esc_timeout_ms)
}
