///|
async fn write_line(tty : @tty.Tty, line : String) -> Unit {
  tty.write(line)
  tty.write("\r\n")
}

///|
async fn run_raw_loop(tty : @tty.Tty) -> Unit {
  while true {
    match tty.read_event() {
      Input(Key({ code: Char('q'), .. })) => {
        write_line(tty, "q pressed; leaving raw mode")
        break
      }
      event => {
        // Debug rendering can contain bare LF, which does not return to
        // column one in raw mode. Keep each event on one logical line.
        let text = Repr(event)
          .to_string()
          .split("\n")
          .map(line => line.trim())
          .join(" ")
        write_line(tty, "event: \{text}")
      }
    }
  }
}

///|
async fn main {
  let tty = @tty.Tty::open()
  defer tty.close()
  write_line(tty, "raw-mode demo")
  write_line(
    tty, "The program will switch the terminal to raw mode and print one decoded event per key press.",
  )
  write_line(
    tty, "Checks: keys should print immediately; Enter should not be required.",
  )
  write_line(
    tty, "Ctrl-C should print a key event instead of terminating the process.",
  )
  write_line(tty, "Press q to restore the terminal and exit.")
  write_line(tty, "If the terminal is left raw after a crash, run: stty sane")
  write_line(tty, "")
  write_line(tty, "entering raw mode...")
  let state = tty.enter_raw_mode()
  {
    defer tty.leave_raw_mode(state)
    write_line(tty, "raw mode active")
    run_raw_loop(tty)
  }
  write_line(tty, "terminal restored")
}
