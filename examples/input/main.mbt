///|
let prompt : String = "> "

///|
let esc_timeout_ms : Int = 50

///|
async fn writeln(tty : @tty.Tty, line : String) -> Unit {
  tty.write(line)
  tty.write("\r\n")
}

///|
async fn redraw_input(tty : @tty.Tty, buffer : String, status : String) -> Unit {
  tty.write("\r")
  tty.erase_line_all()
  tty.write(prompt)
  tty.write(buffer)
  if status.length() > 0 {
    let suffix = "  \{status}"
    tty.write(suffix)
    tty.cursor_back(display_width(suffix))
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
async fn submit(tty : @tty.Tty, line : String) -> Unit {
  tty.write("\r")
  tty.erase_line_all()
  writeln(tty, "\{prompt}\{line}")
  writeln(tty, "submitted: \{line}")
  redraw_input(tty, "", "submitted")
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
    Char(ch) => "\{ch}"
    Text => "Text"
    Enter => "Enter"
    Tab => "Tab"
    Backspace => "Backspace"
    Delete => "Delete"
    Escape => "Escape"
    Up => "Up"
    Down => "Down"
    Left => "Left"
    Right => "Right"
    Home => "Home"
    End => "End"
    PageUp => "PageUp"
    PageDown => "PageDown"
    Insert => "Insert"
    F1 => "F1"
    F2 => "F2"
    F3 => "F3"
    F4 => "F4"
    F5 => "F5"
    F6 => "F6"
    F7 => "F7"
    F8 => "F8"
    F9 => "F9"
    F10 => "F10"
    F11 => "F11"
    F12 => "F12"
  }
  "event: Key \{modifier}\{name}"
}

///|
fn describe_mouse_button(button : @tty/input.MouseButton) -> String {
  match button {
    Left => "Left"
    Middle => "Middle"
    Right => "Right"
  }
}

///|
fn describe_mouse_scroll(scroll : @tty/input.MouseScroll) -> String {
  match scroll {
    Up => "Up"
    Down => "Down"
    Left => "Left"
    Right => "Right"
  }
}

///|
fn describe_mouse_kind(kind : @tty/input.MouseEventKind) -> String {
  match kind {
    Press(button) => "Press \{describe_mouse_button(button)}"
    Release(button) => "Release \{describe_mouse_button(button)}"
    Drag(button) => "Drag \{describe_mouse_button(button)}"
    Move => "Move"
    Scroll(scroll) => "Scroll \{describe_mouse_scroll(scroll)}"
  }
}

///|
fn describe_mouse(mouse : @tty/input.MouseEvent) -> String {
  let modifier = describe_modifiers(mouse.modifiers)
  "event: Mouse \{modifier}\{describe_mouse_kind(mouse.kind)} row=\{mouse.row} col=\{mouse.col}"
}

///|
async fn run_input_buffer(tty : @tty.Tty) -> Unit {
  let mut buffer = ""
  writeln(tty, "input buffer demo")
  writeln(
    tty,
    "Type text or use the mouse. Enter submits. Backspace deletes one grapheme. Esc uses a \{esc_timeout_ms}ms timeout. Ctrl-C exits.",
  )
  redraw_input(tty, buffer, "")
  while true {
    let event = tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    match event {
      Input(input) =>
        match input {
          Key(key) =>
            match key.code {
              Char('c') if key.modifiers.ctrl() => {
                tty.write("\r")
                tty.erase_line_all()
                writeln(tty, "exiting")
                break
              }
              Enter => {
                submit(tty, buffer)
                buffer = ""
              }
              Backspace => {
                buffer = delete_last_grapheme(buffer)
                redraw_input(tty, buffer, "event: Backspace")
              }
              Text =>
                match key.text {
                  Some(text) => {
                    buffer = buffer + text
                    redraw_input(tty, buffer, describe_key(key))
                  }
                  None => redraw_input(tty, buffer, describe_key(key))
                }
              Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() => {
                let text = match key.text {
                  Some(text) => text
                  None => [ch]
                }
                buffer = buffer + text
                redraw_input(tty, buffer, describe_key(key))
              }
              _ => redraw_input(tty, buffer, describe_key(key))
            }
          Unknown(bytes) =>
            redraw_input(
              tty,
              buffer,
              "event: Unknown \{bytes.length()} bytes [\{describe_bytes(bytes)}]",
            )
          Paste(text) => {
            buffer = buffer + text
            redraw_input(
              tty,
              buffer,
              "event: Paste \{display_width(text)} cols",
            )
          }
          Mouse(mouse) => redraw_input(tty, buffer, describe_mouse(mouse))
        }
      Resize(_) => redraw_input(tty, buffer, "")
    }
  }
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  tty.with_raw_mode(() => {
    tty.with_bracketed_paste(() => {
      tty.with_mouse(Motion, () => run_input_buffer(tty))
    })
  })
}
