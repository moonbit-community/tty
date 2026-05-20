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
async fn redraw_input(buffer : String, status : String) -> Unit {
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  @tty.stdout.write(prompt)
  @tty.stdout.write(buffer)
  if status.length() > 0 {
    let suffix = "  \{status}"
    @tty.stdout.write(suffix)
    @tty.stdout.write(@tty/vt.cursor_back(display_width(suffix)))
  }
}

///|
fn display_width(text : String) -> Int {
  @unicodewidth.str_width(text)
}

///|
fn delete_last_grapheme(text : String) -> String {
  let graphemes = @grapheme.graphemes(text)
  let length = graphemes.length()
  if length == 0 {
    ""
  } else {
    graphemes[:length - 1].to_string()
  }
}

///|
async fn submit(line : String) -> Unit {
  @tty.stdout.write("\r")
  @tty.stdout.write(@tty/vt.erase_line_all)
  writeln("\{prompt}\{line}")
  writeln("submitted: \{line}")
  redraw_input("", "submitted")
}

///|
fn byte_to_hex(byte : Byte) -> String {
  let digits : ReadOnlyArray[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  ['0', 'x', digits[byte.to_int() / 16], digits[byte.to_int() % 16]]
}

///|
fn describe_bytes(bytes : Bytes) -> String {
  let builder = StringBuilder()
  for i in 0..<bytes.length() {
    if i > 0 {
      builder.write_string(" ")
    }
    builder.write_string(byte_to_hex(bytes[i]))
  }
  builder.to_string()
}

///|
fn describe_modifiers(modifiers : @tty/input.KeyModifiers) -> String {
  let builder = StringBuilder()
  if modifiers.ctrl() {
    builder.write_string("Ctrl+")
  }
  if modifiers.alt() {
    builder.write_string("Alt+")
  }
  if modifiers.shift() {
    builder.write_string("Shift+")
  }
  if modifiers.meta() {
    builder.write_string("Meta+")
  }
  builder.to_string()
}

///|
fn describe_key(key : @tty/input.KeyEvent) -> String {
  let modifier = describe_modifiers(key.modifiers)
  let name = match key.code {
    @tty/input.Char(ch) => "\{ch}"
    @tty/input.Text => "Text"
    @tty/input.Enter => "Enter"
    @tty/input.Tab => "Tab"
    @tty/input.Backspace => "Backspace"
    @tty/input.Delete => "Delete"
    @tty/input.Escape => "Escape"
    @tty/input.Up => "Up"
    @tty/input.Down => "Down"
    @tty/input.Left => "Left"
    @tty/input.Right => "Right"
    @tty/input.Home => "Home"
    @tty/input.End => "End"
    @tty/input.PageUp => "PageUp"
    @tty/input.PageDown => "PageDown"
    @tty/input.Insert => "Insert"
    @tty/input.F1 => "F1"
    @tty/input.F2 => "F2"
    @tty/input.F3 => "F3"
    @tty/input.F4 => "F4"
    @tty/input.F5 => "F5"
    @tty/input.F6 => "F6"
    @tty/input.F7 => "F7"
    @tty/input.F8 => "F8"
    @tty/input.F9 => "F9"
    @tty/input.F10 => "F10"
    @tty/input.F11 => "F11"
    @tty/input.F12 => "F12"
  }
  "event: Key \{modifier}\{name}"
}

///|
async fn run_input_buffer(tty : @tty.Tty) -> Unit {
  let mut buffer = ""
  writeln("input buffer demo")
  writeln(
    "Type text. Enter submits. Backspace deletes one grapheme. Esc uses a \{esc_timeout_ms}ms timeout. Ctrl-C exits.",
  )
  redraw_input(buffer, "")
  while true {
    let event = tty.read_event(esc_timeout=esc_timeout_ms) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    match event {
      Key(key) =>
        match key.code {
          Char('c') if key.modifiers.ctrl() => {
            @tty.stdout.write("\r")
            @tty.stdout.write(@tty/vt.erase_line_all)
            writeln("exiting")
            break
          }
          Enter => {
            submit(buffer)
            buffer = ""
          }
          Backspace => {
            buffer = delete_last_grapheme(buffer)
            redraw_input(buffer, "event: Backspace")
          }
          Text =>
            match key.text {
              Some(text) => {
                buffer = buffer + text
                redraw_input(buffer, describe_key(key))
              }
              None => redraw_input(buffer, describe_key(key))
            }
          Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() => {
            let text = match key.text {
              Some(text) => text
              None => [ch]
            }
            buffer = buffer + text
            redraw_input(buffer, describe_key(key))
          }
          _ => redraw_input(buffer, describe_key(key))
        }
      @tty/input.Unknown(bytes) =>
        redraw_input(
          buffer,
          "event: Unknown \{bytes.length()} bytes [\{describe_bytes(bytes)}]",
        )
    }
  }
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  tty.with_raw_mode(() => run_input_buffer(tty))
}
