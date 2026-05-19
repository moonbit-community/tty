///|
let prompt : String = "> "

///|
async fn writeln(line : String) -> Unit {
  @tty.stdout.write(line)
  @tty.stdout.write("\r\n")
}

///|
async fn redraw_input(buffer : Array[Byte]) -> Unit {
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  @tty.stdout.write(prompt)
  @tty.stdout.write(Bytes::from_array(buffer))
}

///|
async fn submit(buffer : Array[Byte]) -> Unit {
  let line = Bytes::from_array(buffer).to_unchecked_string()
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  writeln("\{prompt}\{line}")
  writeln("submitted: \{line}")
  buffer.clear()
  redraw_input(buffer)
}

///|
async fn run_input_buffer() -> Unit {
  let buffer : Array[Byte] = []
  writeln("input buffer demo")
  writeln(
    "Type printable ASCII. Enter submits. Backspace deletes. Ctrl-C exits.",
  )
  redraw_input(buffer)
  while true {
    let byte = @tty.stdin.read_byte() catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    match byte {
      b'\x03' => {
        @tty.stdout.write("\r")
        @tty.stdout.write(@tty/vt.erase_line_all)
        writeln("exiting")
        break
      }
      b'\r' | b'\n' => submit(buffer)
      b'\x7f' | b'\x08' => {
        ignore(buffer.pop())
        redraw_input(buffer)
      }
      0x20..<0x7f => {
        buffer.push(byte)
        redraw_input(buffer)
      }
      _ => ()
    }
  }
}

///|
async fn main {
  @tty.stdin.with_raw_mode(run_input_buffer)
}
