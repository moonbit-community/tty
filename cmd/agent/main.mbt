///|
let esc_timeout_ms : Int = 50

///|
let input_text_rows : Int = 2

///|
priv struct AgentSize {
  cols : Int
}

///|
fn terminal_size() -> AgentSize {
  try @tty.stdout.window_size() catch {
    _ => { cols: 80 }
  } noraise {
    size => { cols: if size.cols < 1 { 80 } else { size.cols } }
  }
}

///|
fn display_width(text : String) -> Int {
  @unicodewidth.str_width(text)
}

///|
fn fit_line(text : String, cols : Int) -> String {
  if cols <= 0 {
    ""
  } else {
    let builder = StringBuilder()
    let mut width = 0
    for grapheme in @grapheme.grapheme_iter(text) {
      let next_width = @unicodewidth.str_width(grapheme)
      if width + next_width > cols {
        break
      }
      builder.write_stringview(grapheme)
      width = width + next_width
    }
    builder.to_string()
  }
}

///|
fn split_input_lines(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).collect()
}

///|
fn line_at(lines : Array[String], index : Int) -> String {
  if index < 0 || index >= lines.length() {
    ""
  } else {
    lines[index]
  }
}

///|
fn clamp_int(value : Int, min_value : Int, max_value : Int) -> Int {
  if value < min_value {
    min_value
  } else if value > max_value {
    max_value
  } else {
    value
  }
}

///|
fn grapheme_count(text : String) -> Int {
  @grapheme.graphemes(text).length()
}

///|
fn grapheme_slice(text : String, start : Int, end : Int) -> String {
  let graphemes = @grapheme.graphemes(text)
  let length = graphemes.length()
  let start = clamp_int(start, 0, length)
  let end = clamp_int(end, start, length)
  graphemes[start:end].to_string()
}

///|
fn is_newline_grapheme(grapheme : StringView) -> Bool {
  grapheme.to_owned() == "\n"
}

///|
fn line_count(text : String) -> Int {
  split_input_lines(text).length()
}

///|
fn line_display_width(lines : Array[String], line : Int) -> Int {
  display_width(line_at(lines, line))
}

///|
fn max_view_start(text : String) -> Int {
  let value = line_count(text) - input_text_rows
  if value < 0 {
    0
  } else {
    value
  }
}

///|
fn clamp_view_start(text : String, view_start : Int) -> Int {
  clamp_int(view_start, 0, max_view_start(text))
}

///|
priv struct CursorPoint {
  line : Int
  grapheme_column : Int
  display_column : Int
}

///|
fn cursor_point_for(text : String, cursor : Int) -> CursorPoint {
  let target = clamp_int(cursor, 0, grapheme_count(text))
  let mut index = 0
  let mut line = 0
  let mut grapheme_column = 0
  let mut display_column = 0
  for grapheme in @grapheme.grapheme_iter(text) {
    if index >= target {
      break
    }
    if is_newline_grapheme(grapheme) {
      line = line + 1
      grapheme_column = 0
      display_column = 0
    } else {
      grapheme_column = grapheme_column + 1
      display_column = display_column + @unicodewidth.str_width(grapheme)
    }
    index = index + 1
  }
  { line, grapheme_column, display_column }
}

///|
fn line_start_cursor(text : String, line : Int) -> Int {
  let line = clamp_int(line, 0, line_count(text) - 1)
  if line == 0 {
    0
  } else {
    let mut index = 0
    let mut current_line = 0
    for grapheme in @grapheme.grapheme_iter(text) {
      index = index + 1
      if is_newline_grapheme(grapheme) {
        current_line = current_line + 1
        if current_line == line {
          break
        }
      }
    }
    index
  }
}

///|
fn cursor_for_line_display_column(
  text : String,
  line : Int,
  display_column : Int,
) -> Int {
  let lines = split_input_lines(text)
  let line = clamp_int(line, 0, lines.length() - 1)
  let target = clamp_int(display_column, 0, line_display_width(lines, line))
  let mut grapheme_column = 0
  let mut width = 0
  for grapheme in @grapheme.grapheme_iter(line_at(lines, line)) {
    let next_width = @unicodewidth.str_width(grapheme)
    if width + next_width > target {
      break
    }
    width = width + next_width
    grapheme_column = grapheme_column + 1
  }
  line_start_cursor(text, line) + grapheme_column
}

///|
fn ensure_cursor_visible(text : String, cursor : Int, view_start : Int) -> Int {
  let point = cursor_point_for(text, cursor)
  let mut start = clamp_view_start(text, view_start)
  if point.line < start {
    start = point.line
  } else if point.line >= start + input_text_rows {
    start = point.line - input_text_rows + 1
  }
  clamp_view_start(text, start)
}

///|
priv struct Editor {
  text : String
  cursor : Int
  preferred_column : Int?
  view_start : Int
}

///|
fn make_editor(
  text : String,
  cursor : Int,
  preferred_column : Int?,
  view_start : Int,
) -> Editor {
  let cursor = clamp_int(cursor, 0, grapheme_count(text))
  let view_start = ensure_cursor_visible(text, cursor, view_start)
  { text, cursor, preferred_column, view_start }
}

///|
fn Editor::new() -> Editor {
  Editor::from_text("")
}

///|
fn Editor::from_text(text : String) -> Editor {
  make_editor(text, grapheme_count(text), None, 0)
}

///|
fn Editor::cursor_point(self : Editor) -> CursorPoint {
  cursor_point_for(self.text, self.cursor)
}

///|
fn Editor::move_to_cursor(
  self : Editor,
  cursor : Int,
  preferred_column : Int?,
) -> Editor {
  make_editor(self.text, cursor, preferred_column, self.view_start)
}

///|
fn Editor::insert(self : Editor, text : String) -> Editor {
  let prefix = grapheme_slice(self.text, 0, self.cursor)
  let suffix = grapheme_slice(self.text, self.cursor, grapheme_count(self.text))
  make_editor(
    prefix + text + suffix,
    self.cursor + grapheme_count(text),
    None,
    self.view_start,
  )
}

///|
fn Editor::delete_before(self : Editor) -> Editor {
  if self.cursor <= 0 {
    make_editor(self.text, 0, None, self.view_start)
  } else {
    let prefix = grapheme_slice(self.text, 0, self.cursor - 1)
    let suffix = grapheme_slice(
      self.text,
      self.cursor,
      grapheme_count(self.text),
    )
    make_editor(prefix + suffix, self.cursor - 1, None, self.view_start)
  }
}

///|
fn Editor::delete_after(self : Editor) -> Editor {
  let length = grapheme_count(self.text)
  if self.cursor >= length {
    make_editor(self.text, self.cursor, None, self.view_start)
  } else {
    let prefix = grapheme_slice(self.text, 0, self.cursor)
    let suffix = grapheme_slice(self.text, self.cursor + 1, length)
    make_editor(prefix + suffix, self.cursor, None, self.view_start)
  }
}

///|
fn Editor::move_left(self : Editor) -> Editor {
  self.move_to_cursor(self.cursor - 1, None)
}

///|
fn Editor::move_right(self : Editor) -> Editor {
  self.move_to_cursor(self.cursor + 1, None)
}

///|
fn Editor::move_home(self : Editor) -> Editor {
  let point = self.cursor_point()
  self.move_to_cursor(line_start_cursor(self.text, point.line), None)
}

///|
fn Editor::move_end(self : Editor) -> Editor {
  let point = self.cursor_point()
  let lines = split_input_lines(self.text)
  self.move_to_cursor(
    cursor_for_line_display_column(
      self.text,
      point.line,
      line_display_width(lines, point.line),
    ),
    None,
  )
}

///|
fn Editor::move_vertical(self : Editor, delta : Int) -> Editor {
  let point = self.cursor_point()
  let lines = split_input_lines(self.text)
  let target_line = clamp_int(point.line + delta, 0, lines.length() - 1)
  let preferred_column = self.preferred_column.unwrap_or(point.display_column)
  self.move_to_cursor(
    cursor_for_line_display_column(self.text, target_line, preferred_column),
    Some(preferred_column),
  )
}

///|
fn input_prefix(row_index : Int, start : Int) -> String {
  if start == 0 && row_index == 0 {
    "> "
  } else {
    "  "
  }
}

///|
fn editor_cursor_row(editor : Editor) -> Int {
  let row = editor.cursor_point().line - editor.view_start
  if row < 0 {
    0
  } else if row >= input_text_rows {
    input_text_rows - 1
  } else {
    row
  }
}

///|
fn input_cursor_offset(editor : Editor, cols : Int) -> Int {
  let lines = split_input_lines(editor.text)
  let point = editor.cursor_point()
  let row = editor_cursor_row(editor)
  let prefix = input_prefix(row, editor.view_start)
  let line = line_at(lines, point.line)
  let before_cursor = grapheme_slice(line, 0, point.grapheme_column)
  let visible = fit_line(before_cursor, cols - display_width(prefix))
  display_width(prefix) + display_width(visible)
}

///|
fn fake_response(input : String) -> String {
  let display = input.replace_all(old="\n", new=" / ")
  "received: \{display}"
}

///|
async fn write(text : String) -> Unit {
  @tty.stdout.write(text)
}

///|
async fn write_bytes(bytes : Bytes) -> Unit {
  @tty.stdout.write(bytes)
}

///|
async fn move_up(rows : Int) -> Unit {
  if rows > 0 {
    write_bytes(@tty/vt.cursor_up(rows))
  }
}

///|
async fn move_forward(cols : Int) -> Unit {
  if cols > 0 {
    write_bytes(@tty/vt.cursor_forward(cols))
  }
}

///|
async fn write_colored_text(
  color : @vt_color.BasicColor,
  text : String,
) -> Unit {
  write_bytes(@vt_color.foreground(@vt_color.Basic(color)))
  write(text)
  write_bytes(@vt_color.reset_foreground)
}

///|
async fn erase_current_line() -> Unit {
  write("\r")
  write_bytes(@tty/vt.erase_line_all)
}

///|
async fn render_separator_current(cols : Int) -> Unit {
  erase_current_line()
  write_bytes(@vt_color.foreground(@vt_color.Basic(@vt_color.BrightBlack)))
  write(String::make(cols, '-'))
  write_bytes(@vt_color.reset_foreground)
}

///|
async fn render_prompt_current(
  prefix : String,
  line : String,
  cols : Int,
) -> Unit {
  erase_current_line()
  write_colored_text(@vt_color.BrightGreen, prefix)
  write(fit_line(line, cols - display_width(prefix)))
}

///|
async fn render_status_current(status : String, cols : Int) -> Unit {
  erase_current_line()
  write_bytes(@vt_color.foreground(@vt_color.Basic(@vt_color.BrightBlack)))
  let text = if status.length() == 0 {
    "Enter send  Ctrl-J newline  Arrows move  Backspace edit  Ctrl-C quit"
  } else {
    status
  }
  write(fit_line(text, cols))
  write_bytes(@vt_color.reset_foreground)
}

///|
async fn render_input_at_cursor(
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  let lines = split_input_lines(editor.text)
  let start = editor.view_start
  render_separator_current(size.cols)
  write("\r\n")
  for row in 0..<input_text_rows {
    let absolute = start + row
    render_prompt_current(
      input_prefix(row, start),
      line_at(lines, absolute),
      size.cols,
    )
    write("\r\n")
  }
  render_status_current(status, size.cols)
}

///|
async fn move_from_input_cursor_to_top(editor : Editor) -> Unit {
  move_up(1 + editor_cursor_row(editor))
  write("\r")
}

///|
async fn place_input_cursor(editor : Editor, size : AgentSize) -> Unit {
  let row = editor_cursor_row(editor)
  move_up(input_text_rows - row)
  write("\r")
  move_forward(input_cursor_offset(editor, size.cols))
}

///|
async fn redraw_input_from(
  old_editor : Editor,
  new_editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  move_from_input_cursor_to_top(old_editor)
  render_input_at_cursor(new_editor, status, size)
  place_input_cursor(new_editor, size)
}

///|
async fn render_transcript_row(
  prefix : String,
  color : @vt_color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  erase_current_line()
  write_colored_text(color, prefix)
  write(fit_line(text, size.cols - display_width(prefix)))
  write("\r\n")
}

///|
async fn render_transcript_at_cursor(
  role : String,
  color : @vt_color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  let prefix = "\{role}: "
  let continuation = String::make(display_width(prefix), ' ')
  let lines = split_input_lines(text)
  for i in 0..<lines.length() {
    let row_prefix = if i == 0 { prefix } else { continuation }
    render_transcript_row(row_prefix, color, line_at(lines, i), size)
  }
}

///|
async fn append_transcript(
  cursor_editor : Editor,
  role : String,
  color : @vt_color.BasicColor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  move_from_input_cursor_to_top(cursor_editor)
  render_transcript_at_cursor(role, color, text, size)
  render_input_at_cursor(editor, status, size)
  place_input_cursor(editor, size)
}

///|
async fn append_user(
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  append_transcript(
    cursor_editor,
    "user",
    @vt_color.BrightCyan,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn append_agent(
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  append_transcript(
    cursor_editor,
    "agent",
    @vt_color.BrightMagenta,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn restore_terminal() -> Unit {
  write_bytes(@tty/vt.reset_top_bottom_margins)
  write_bytes(@vt_color.reset_all)
  write_bytes(@tty/vt.show_cursor)
}

///|
async fn leave_agent() -> Unit {
  restore_terminal()
  write("\r\n")
}

///|
fn text_from_key(key : @tty/input.KeyEvent) -> String? {
  match key.code {
    @tty/input.Text => key.text
    @tty/input.Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() =>
      match key.text {
        Some(text) => Some(text)
        None => Some([ch])
      }
    _ => None
  }
}

///|
fn is_newline_key(key : @tty/input.KeyEvent) -> Bool {
  match key.code {
    @tty/input.Char('j') if key.modifiers.ctrl() => true
    _ => false
  }
}

///|
async fn submit(editor : Editor) -> Unit {
  let empty = Editor::new()
  let mut size = terminal_size()
  redraw_input_from(editor, empty, "sending...", size)
  append_user(empty, editor.text, empty, "sending...", size)
  size = terminal_size()
  append_agent(empty, fake_response(editor.text), empty, "ready", size)
}

///|
async fn run_agent() -> Unit {
  let events = @tty.stdin.event_reader()
  let mut editor = Editor::new()
  let mut size = terminal_size()
  write_bytes(@tty/vt.show_cursor)
  render_transcript_at_cursor(
    "system",
    @vt_color.BrightBlack,
    "primary-screen agent demo",
    size,
  )
  render_transcript_at_cursor(
    "system",
    @vt_color.BrightBlack,
    "type a message and press Enter",
    size,
  )
  render_input_at_cursor(editor, "", size)
  place_input_cursor(editor, size)
  while true {
    let event = events.read_event(esc_timeout=esc_timeout_ms) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    size = terminal_size()
    match event {
      @tty/input.Key(key) =>
        match key.code {
          @tty/input.Char('c') if key.modifiers.ctrl() => break
          @tty/input.Char('d') if key.modifiers.ctrl() &&
            editor.text.length() == 0 => break
          @tty/input.Enter =>
            if editor.text.length() > 0 {
              submit(editor)
              editor = Editor::new()
            } else {
              redraw_input_from(editor, editor, "empty input", size)
            }
          @tty/input.Up => {
            let old_editor = editor
            editor = editor.move_vertical(-1)
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Down => {
            let old_editor = editor
            editor = editor.move_vertical(1)
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Left => {
            let old_editor = editor
            editor = editor.move_left()
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Right => {
            let old_editor = editor
            editor = editor.move_right()
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Home => {
            let old_editor = editor
            editor = editor.move_home()
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.End => {
            let old_editor = editor
            editor = editor.move_end()
            redraw_input_from(old_editor, editor, "", size)
          }
          _ if is_newline_key(key) => {
            let old_editor = editor
            editor = editor.insert("\n")
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Backspace => {
            let old_editor = editor
            editor = editor.delete_before()
            redraw_input_from(old_editor, editor, "", size)
          }
          @tty/input.Delete => {
            let old_editor = editor
            editor = editor.delete_after()
            redraw_input_from(old_editor, editor, "", size)
          }
          _ =>
            match text_from_key(key) {
              Some(text) => {
                let old_editor = editor
                editor = editor.insert(text)
                redraw_input_from(old_editor, editor, "", size)
              }
              None => redraw_input_from(editor, editor, "ignored key", size)
            }
        }
      @tty/input.Unknown(bytes) =>
        redraw_input_from(
          editor,
          editor,
          "unknown input: \{bytes.length()} bytes",
          size,
        )
    }
  }
  leave_agent()
}

///|
async fn main {
  try @tty.stdin.with_raw_mode(run_agent) catch {
    error => {
      restore_terminal()
      raise error
    }
  } noraise {
    _ => ()
  }
}
