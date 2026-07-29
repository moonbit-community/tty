///|
/// Query the visible terminal window size.
pub async fn Tty::window_size(self : Self) -> WindowSize {
  match
    @client.Sidecar::get().call(
      WinSize(which=@client.stdio_slot_or_invalid(self.output_fd)),
    ) {
    WinSize(rows~, cols~) => { rows, cols }
    Error(errno~) => raise @os_error.OSError(errno, context="Tty::window_size")
    _ => raise @sidecar.ProtocolViolation
  }
}
