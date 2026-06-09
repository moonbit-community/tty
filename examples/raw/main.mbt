///|
let number_to_xdigit : ReadOnlyArray[Byte] = [
  b'0', b'1', b'2', b'3', b'4', b'5', b'6', b'7', b'8', b'9', b'a', b'b', b'c', b'd',
  b'e', b'f',
]

///|
fn byte_to_printable_char(byte : Byte) -> Char? {
  if byte >= b' ' && byte <= b'~' {
    Some(byte.to_char())
  } else {
    None
  }
}

///|
fn byte_to_raw_line(byte : Byte) -> String {
  let line = StringBuilder(size_hint=16)
  line.write_string("0x")
  line.write_char(number_to_xdigit[byte.to_int() / 16].to_char())
  line.write_char(number_to_xdigit[byte.to_int() % 16].to_char())
  match byte_to_printable_char(byte) {
    Some(char) => {
      line.write_string(" ")
      line.write_string(char.escape(quote=true))
    }
    None => ()
  }
  line.write_string("\r\n")
  line.to_string()
}

///|
async fn write_line(tty : @tty.Tty, line : String) -> Unit {
  tty.write(line)
  tty.write("\r\n")
}

///|
async fn run_raw_loop(tty : @tty.Tty) -> Unit {
  while true {
    let byte = @async/stdio.stdin.read_exactly(1)[0] catch {
        @async/io.ReaderClosed => break
        error => raise error
      }
    if byte == b'q' {
      write_line(tty, "q pressed; leaving raw mode")
      break
    }
    tty.write("read ")
    tty.write(byte_to_raw_line(byte))
  }
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  write_line(tty, "raw-mode demo")
  write_line(
    tty, "The program will switch stdin to raw mode and print one byte per key press.",
  )
  write_line(
    tty, "Checks: normal keys should print immediately; Enter should not be required.",
  )
  write_line(
    tty, "Ctrl-C should print 0x03 instead of terminating the process.",
  )
  write_line(
    tty, "Backspace is usually 0x7f or 0x08. Press q to restore and exit.",
  )
  write_line(tty, "If the terminal is left raw after a crash, run: stty sane")
  write_line(tty, "")
  write_line(tty, "entering raw mode...")
  let state = tty.enter_raw_mode()
  let mut restored = false
  try {
    write_line(tty, "raw mode active")
    run_raw_loop(tty)
  } catch {
    error => {
      tty.leave_raw_mode(state)
      restored = true
      raise error
    }
  }
  if !restored {
    tty.leave_raw_mode(state)
  }
  write_line(tty, "terminal restored")
}
