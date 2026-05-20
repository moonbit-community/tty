///|
let prompt : String = "> "

///|
let esc_timeout_ms : Int = 50

///|
async fn writeln(line : String) -> Unit {
  @tty.stdout.write(line)
  @tty.stdout.write("\r\n")
}

///|
async fn redraw_input(buffer : Array[Byte], status : String) -> Unit {
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  @tty.stdout.write(prompt)
  @tty.stdout.write(Bytes::from_array(buffer))
  if status.length() > 0 {
    let suffix = "  \{status}"
    @tty.stdout.write(suffix)
    @tty.stdout.write(@tty/vt.cursor_back(suffix.length()))
  }
}

///|
fn ascii_bytes_to_string(buffer : Array[Byte]) -> String {
  let builder = StringBuilder(size_hint=buffer.length())
  for byte in buffer {
    builder.write_char(byte.to_char())
  }
  builder.to_string()
}

///|
async fn submit(buffer : Array[Byte]) -> Unit {
  let line = ascii_bytes_to_string(buffer)
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  writeln("\{prompt}\{line}")
  writeln("submitted: \{line}")
  buffer.clear()
  redraw_input(buffer, "submitted")
}

///|
fn printable_ascii_byte(ch : Char) -> Byte? {
  let code = ch.to_int()
  if code >= 0x20 && code < 0x7f {
    Some(code.to_byte())
  } else {
    None
  }
}

///|
fn describe_key(key : @tty_input.KeyEvent) -> String {
  let modifier = if key.modifiers.ctrl() {
    "Ctrl+"
  } else if key.modifiers.alt() {
    "Alt+"
  } else if key.modifiers.shift() {
    "Shift+"
  } else if key.modifiers.meta() {
    "Meta+"
  } else {
    ""
  }
  match key.code {
    @tty_input.Char(ch) => "event: Key \{modifier}\{ch}"
    @tty_input.Text => "event: Text"
    @tty_input.Enter => "event: Enter"
    @tty_input.Tab => "event: Tab"
    @tty_input.Backspace => "event: Backspace"
    @tty_input.Delete => "event: Delete"
    @tty_input.Escape => "event: Escape"
    @tty_input.Up => "event: Up"
    @tty_input.Down => "event: Down"
    @tty_input.Left => "event: Left"
    @tty_input.Right => "event: Right"
    @tty_input.Home => "event: Home"
    @tty_input.End => "event: End"
    @tty_input.PageUp => "event: PageUp"
    @tty_input.PageDown => "event: PageDown"
    @tty_input.Insert => "event: Insert"
    @tty_input.F(n) => "event: F\{n}"
  }
}

///|
async fn run_input_buffer() -> Unit {
  let buffer : Array[Byte] = []
  writeln("input buffer demo")
  writeln(
    "Type printable ASCII. Enter submits. Backspace deletes. Esc uses a \{esc_timeout_ms}ms timeout. Ctrl-C exits.",
  )
  redraw_input(buffer, "")
  while true {
    let event = @tty.stdin.read_event(esc_timeout=esc_timeout_ms) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    match event {
      @tty_input.Key(key) =>
        match key.code {
          @tty_input.Char('c') if key.modifiers.ctrl() => {
            @tty.stdout.write("\r")
            @tty.stdout.write(@tty/vt.erase_line_all)
            writeln("exiting")
            break
          }
          @tty_input.Enter => submit(buffer)
          @tty_input.Backspace => {
            ignore(buffer.pop())
            redraw_input(buffer, "event: Backspace")
          }
          @tty_input.Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() =>
            match printable_ascii_byte(ch) {
              Some(byte) => {
                buffer.push(byte)
                redraw_input(buffer, describe_key(key))
              }
              None => redraw_input(buffer, describe_key(key))
            }
          _ => redraw_input(buffer, describe_key(key))
        }
      @tty_input.Unknown(bytes) =>
        redraw_input(buffer, "event: Unknown \{bytes.length()} bytes")
    }
  }
}

///|
async fn main {
  @tty.stdin.with_raw_mode(run_input_buffer)
}
