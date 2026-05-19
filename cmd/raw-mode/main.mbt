///|
let number_to_xdigit : ReadOnlyArray[Byte] = [
  b'0', b'1', b'2', b'3', b'4', b'5', b'6', b'7', b'8', b'9', b'a', b'b', b'c', b'd',
  b'e', b'f',
]

///|
fn byte_to_hex_line(byte : Byte) -> Bytes {
  let buf : FixedArray[Byte] = FixedArray::make(6, 0)
  buf[0] = b'0'
  buf[1] = b'x'
  buf[2] = number_to_xdigit[byte.to_int() / 16]
  buf[3] = number_to_xdigit[byte.to_int() % 16]
  buf[4] = b'\r'
  buf[5] = b'\n'
  buf.unsafe_reinterpret_as_bytes()
}

///|
async fn write_line(line : String) -> Unit {
  @tty.stdout.write(line)
  @tty.stdout.write("\r\n")
}

///|
async fn run_raw_loop() -> Unit {
  while true {
    let byte = @tty.stdin.read_byte() catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    if byte == b'q' {
      write_line("q pressed; leaving raw mode")
      break
    }
    @tty.stdout.write("read ")
    @tty.stdout.write(byte_to_hex_line(byte))
  }
}

///|
async fn main {
  write_line("raw-mode demo")
  write_line(
    "The program will switch stdin to raw mode and print one byte per key press.",
  )
  write_line(
    "Checks: normal keys should print immediately; Enter should not be required.",
  )
  write_line("Ctrl-C should print 0x03 instead of terminating the process.")
  write_line("Backspace is usually 0x7f or 0x08. Press q to restore and exit.")
  write_line("If the terminal is left raw after a crash, run: stty sane")
  write_line("")
  write_line("entering raw mode...")
  let state = @tty.stdin.enter_raw_mode()
  let mut restored = false
  try {
    write_line("raw mode active")
    run_raw_loop()
  } catch {
    error => {
      @tty.stdin.leave_raw_mode(state)
      restored = true
      raise error
    }
  }
  if !restored {
    @tty.stdin.leave_raw_mode(state)
  }
  write_line("terminal restored")
}
