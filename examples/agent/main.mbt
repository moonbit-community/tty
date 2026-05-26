///|
let esc_timeout_ms : Int = 50

///|
let queued_submit_delay_ms : Int = 1000

///|
let input_text_rows : Int = 2

///|
let composer_rows : Int = input_text_rows + 2

///|
priv struct AgentSize {
  rows : Int
  cols : Int
}

///|
priv enum AgentEvent {
  Terminal(@tty.Event)
  TerminalClosed
  QueuedInput(text~ : String, shell_mode~ : Bool)
  ShellResult(command~ : String, exit_code~ : Int, output~ : String)
}

///|
fn terminal_size(tty : @tty.Tty) -> AgentSize {
  try tty.window_size() catch {
    _ => { rows: 24, cols: 80 }
  } noraise {
    size =>
      {
        rows: if size.rows < 1 {
          24
        } else {
          size.rows
        },
        cols: if size.cols < 1 {
          80
        } else {
          size.cols
        },
      }
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
  shell_mode : Bool
}

///|
fn make_editor(
  text : String,
  cursor : Int,
  preferred_column : Int?,
  view_start : Int,
  shell_mode? : Bool = false,
) -> Editor {
  let cursor = clamp_int(cursor, 0, grapheme_count(text))
  let view_start = ensure_cursor_visible(text, cursor, view_start)
  { text, cursor, preferred_column, view_start, shell_mode }
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
  make_editor(
    self.text,
    cursor,
    preferred_column,
    self.view_start,
    shell_mode=self.shell_mode,
  )
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
    shell_mode=self.shell_mode,
  )
}

///|
fn Editor::insert_user_text(self : Editor, text : String) -> Editor {
  if !self.shell_mode && self.text.length() == 0 && self.cursor == 0 {
    match text {
      [.. "!", .. rest] => {
        let rest_text = rest.to_owned()
        make_editor(
          rest_text,
          grapheme_count(rest_text),
          None,
          self.view_start,
          shell_mode=true,
        )
      }
      _ => self.insert(text)
    }
  } else {
    self.insert(text)
  }
}

///|
fn Editor::delete_before(self : Editor) -> Editor {
  if self.cursor <= 0 {
    make_editor(self.text, 0, None, self.view_start, shell_mode=false)
  } else {
    let prefix = grapheme_slice(self.text, 0, self.cursor - 1)
    let suffix = grapheme_slice(
      self.text,
      self.cursor,
      grapheme_count(self.text),
    )
    make_editor(
      prefix + suffix,
      self.cursor - 1,
      None,
      self.view_start,
      shell_mode=self.shell_mode,
    )
  }
}

///|
fn Editor::delete_after(self : Editor) -> Editor {
  let length = grapheme_count(self.text)
  if self.cursor >= length {
    make_editor(
      self.text,
      self.cursor,
      None,
      self.view_start,
      shell_mode=self.shell_mode,
    )
  } else {
    let prefix = grapheme_slice(self.text, 0, self.cursor)
    let suffix = grapheme_slice(self.text, self.cursor + 1, length)
    make_editor(
      prefix + suffix,
      self.cursor,
      None,
      self.view_start,
      shell_mode=self.shell_mode,
    )
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
fn input_prefix(
  row_index : Int,
  start : Int,
  shell_mode? : Bool = false,
) -> String {
  if start == 0 && row_index == 0 {
    if shell_mode {
      "! "
    } else {
      "> "
    }
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
  let prefix = input_prefix(
    row,
    editor.view_start,
    shell_mode=editor.shell_mode,
  )
  let line = line_at(lines, point.line)
  let before_cursor = grapheme_slice(line, 0, point.grapheme_column)
  let visible = fit_line(before_cursor, cols - display_width(prefix))
  display_width(prefix) + display_width(visible)
}

///|
fn viewport_top_from_cursor(row : Int, editor : Editor) -> Int {
  let top = row - editor_cursor_row(editor) - 1
  if top < 1 {
    1
  } else {
    top
  }
}

///|
fn max_viewport_top(size : AgentSize) -> Int {
  let top = size.rows - composer_rows + 1
  if top < 1 {
    1
  } else {
    top
  }
}

///|
fn clamp_viewport_top(top : Int, size : AgentSize) -> Int {
  clamp_int(top, 1, max_viewport_top(size))
}

///|
fn viewport_bottom(top : Int) -> Int {
  top + composer_rows - 1
}

///|
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn fake_response(input : String) -> String {
  let display = input.replace_all(old="\n", new=" / ")
  "received: \{display}"
}

///|
fn shell_command_text(input : String) -> String {
  input.trim().to_owned()
}

///|
#cfg(platform="windows")
fn shell_program() -> String {
  "powershell"
}

///|
#cfg(not(platform="windows"))
fn shell_program() -> String {
  "sh"
}

///|
#cfg(platform="windows")
fn shell_args(command : String) -> Array[String] {
  ["-NoProfile", "-Command", command]
}

///|
#cfg(not(platform="windows"))
fn shell_args(command : String) -> Array[String] {
  ["-c", command]
}

///|
fn format_shell_result(
  command : String,
  exit_code : Int,
  output : String,
) -> String {
  let output = output
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .trim(chars="\n")
    .to_owned()
  let command = if command.length() == 0 { "<empty command>" } else { command }
  let header = if exit_code == 0 {
    "$ \{command}"
  } else {
    "$ \{command} (exit \{exit_code})"
  }
  if output.length() == 0 {
    "\{header}\n(no output)"
  } else {
    "\{header}\n\{output}"
  }
}

///|
async fn write(tty : @tty.Tty, text : String) -> Unit {
  tty.write(text)
}

///|
async fn move_up(tty : @tty.Tty, rows : Int) -> Unit {
  if rows > 0 {
    tty.cursor_up(rows)
  }
}

///|
async fn move_forward(tty : @tty.Tty, cols : Int) -> Unit {
  if cols > 0 {
    tty.cursor_forward(cols)
  }
}

///|
async fn write_colored_text(
  tty : @tty.Tty,
  color : @color.BasicColor,
  text : String,
) -> Unit {
  tty.set_foreground(@color.Basic(color))
  write(tty, text)
  tty.reset_foreground()
}

///|
async fn erase_current_line(tty : @tty.Tty) -> Unit {
  write(tty, "\r")
  tty.erase_line_all()
}

///|
async fn render_separator_current(tty : @tty.Tty, cols : Int) -> Unit {
  erase_current_line(tty)
  tty.set_foreground(@color.Basic(@color.BrightBlack))
  write(tty, String::make(cols, '-'))
  tty.reset_foreground()
}

///|
async fn render_prompt_current(
  tty : @tty.Tty,
  prefix : String,
  line : String,
  cols : Int,
) -> Unit {
  erase_current_line(tty)
  write_colored_text(tty, @color.BrightGreen, prefix)
  write(tty, fit_line(line, cols - display_width(prefix)))
}

///|
async fn render_status_current(
  tty : @tty.Tty,
  status : String,
  cols : Int,
) -> Unit {
  erase_current_line(tty)
  tty.set_foreground(@color.Basic(@color.BrightBlack))
  let text = if status.length() == 0 {
    "Enter send  Tab queue  !cmd shell  Ctrl-J newline  Arrows move  Ctrl-C quit"
  } else {
    status
  }
  write(tty, fit_line(text, cols))
  tty.reset_foreground()
}

///|
async fn render_input_at_cursor(
  tty : @tty.Tty,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  let lines = split_input_lines(editor.text)
  let start = editor.view_start
  let shell_mode = editor.shell_mode
  render_separator_current(tty, size.cols)
  write(tty, "\r\n")
  for row in 0..<input_text_rows {
    let absolute = start + row
    render_prompt_current(
      tty,
      input_prefix(row, start, shell_mode~),
      line_at(lines, absolute),
      size.cols,
    )
    write(tty, "\r\n")
  }
  render_status_current(tty, status, size.cols)
}

///|
async fn move_from_input_cursor_to_top(tty : @tty.Tty, editor : Editor) -> Unit {
  move_up(tty, 1 + editor_cursor_row(editor))
  write(tty, "\r")
}

///|
async fn place_input_cursor(
  tty : @tty.Tty,
  editor : Editor,
  size : AgentSize,
) -> Unit {
  let row = editor_cursor_row(editor)
  move_up(tty, input_text_rows - row)
  write(tty, "\r")
  move_forward(tty, input_cursor_offset(editor, size.cols))
}

///|
async fn redraw_input_from(
  tty : @tty.Tty,
  old_editor : Editor,
  new_editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  move_from_input_cursor_to_top(tty, old_editor)
  render_input_at_cursor(tty, new_editor, status, size)
  place_input_cursor(tty, new_editor, size)
}

///|
async fn render_input_at_top(
  tty : @tty.Tty,
  top : Int,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  let lines = split_input_lines(editor.text)
  let start = editor.view_start
  let shell_mode = editor.shell_mode
  tty.set_cursor_position(top, 1)
  render_separator_current(tty, size.cols)
  for row in 0..<input_text_rows {
    tty.set_cursor_position(top + 1 + row, 1)
    render_prompt_current(
      tty,
      input_prefix(row, start, shell_mode~),
      line_at(lines, start + row),
      size.cols,
    )
  }
  tty.set_cursor_position(top + input_text_rows + 1, 1)
  render_status_current(tty, status, size.cols)
}

///|
async fn place_input_cursor_at_top(
  tty : @tty.Tty,
  top : Int,
  editor : Editor,
  size : AgentSize,
) -> Unit {
  tty.set_cursor_position(
    top + 1 + editor_cursor_row(editor),
    1 + input_cursor_offset(editor, size.cols),
  )
}

///|
async fn redraw_input_at_top(
  tty : @tty.Tty,
  top : Int,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  render_input_at_top(tty, top, editor, status, size)
  place_input_cursor_at_top(tty, top, editor, size)
}

///|
async fn render_transcript_row_current(
  tty : @tty.Tty,
  prefix : String,
  color : @color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  erase_current_line(tty)
  write_colored_text(tty, color, prefix)
  write(tty, fit_line(text, size.cols - display_width(prefix)))
}

///|
async fn render_transcript_row(
  tty : @tty.Tty,
  prefix : String,
  color : @color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  render_transcript_row_current(tty, prefix, color, text, size)
  write(tty, "\r\n")
}

///|
async fn render_transcript_at_cursor(
  tty : @tty.Tty,
  role : String,
  color : @color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  let prefix = "\{role}: "
  let continuation = String::make(display_width(prefix), ' ')
  let lines = split_input_lines(text)
  for i in 0..<lines.length() {
    let row_prefix = if i == 0 { prefix } else { continuation }
    render_transcript_row(tty, row_prefix, color, line_at(lines, i), size)
  }
}

///|
async fn append_transcript(
  tty : @tty.Tty,
  cursor_editor : Editor,
  role : String,
  color : @color.BasicColor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  move_from_input_cursor_to_top(tty, cursor_editor)
  render_transcript_at_cursor(tty, role, color, text, size)
  render_input_at_cursor(tty, editor, status, size)
  place_input_cursor(tty, editor, size)
}

///|
async fn append_user(
  tty : @tty.Tty,
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  append_transcript(
    tty,
    cursor_editor,
    "user",
    @color.BrightCyan,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn append_agent(
  tty : @tty.Tty,
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  append_transcript(
    tty,
    cursor_editor,
    "agent",
    @color.BrightMagenta,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn append_shell(
  tty : @tty.Tty,
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Unit {
  append_transcript(
    tty,
    cursor_editor,
    "shell",
    @color.BrightYellow,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn shift_viewport_down_for_insert(
  tty : @tty.Tty,
  top : Int,
  lines : Int,
  size : AgentSize,
) -> Int {
  let space = size.rows - viewport_bottom(top)
  let shift = min_int(lines, if space < 0 { 0 } else { space })
  if shift <= 0 {
    top
  } else {
    tty.set_top_bottom_margins(top, size.rows)
    tty.set_cursor_position(top, 1)
    for _ in 0..<shift {
      tty.reverse_index()
    }
    tty.reset_top_bottom_margins()
    top + shift
  }
}

///|
async fn insert_transcript_row_above_viewport(
  tty : @tty.Tty,
  top : Int,
  prefix : String,
  color : @color.BasicColor,
  text : String,
  size : AgentSize,
) -> Unit {
  let history_bottom = top - 1
  if history_bottom < 1 {
    render_transcript_row(tty, prefix, color, text, size)
  } else {
    tty.set_top_bottom_margins(1, history_bottom)
    tty.set_cursor_position(history_bottom, 1)
    write(tty, "\r\n")
    render_transcript_row_current(tty, prefix, color, text, size)
    tty.reset_top_bottom_margins()
  }
}

///|
async fn append_transcript_above_viewport(
  tty : @tty.Tty,
  top : Int,
  role : String,
  color : @color.BasicColor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Int {
  let prefix = "\{role}: "
  let continuation = String::make(display_width(prefix), ' ')
  let lines = split_input_lines(text)
  let top = clamp_viewport_top(top, size)
  let top = shift_viewport_down_for_insert(tty, top, lines.length(), size)
  for i in 0..<lines.length() {
    let row_prefix = if i == 0 { prefix } else { continuation }
    insert_transcript_row_above_viewport(
      tty,
      top,
      row_prefix,
      color,
      line_at(lines, i),
      size,
    )
  }
  redraw_input_at_top(tty, top, editor, status, size)
  top
}

///|
async fn append_user_above_viewport(
  tty : @tty.Tty,
  top : Int,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Int {
  append_transcript_above_viewport(
    tty,
    top,
    "user",
    @color.BrightCyan,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn append_agent_above_viewport(
  tty : @tty.Tty,
  top : Int,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Int {
  append_transcript_above_viewport(
    tty,
    top,
    "agent",
    @color.BrightMagenta,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn append_shell_above_viewport(
  tty : @tty.Tty,
  top : Int,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Int {
  append_transcript_above_viewport(
    tty,
    top,
    "shell",
    @color.BrightYellow,
    text,
    editor,
    status,
    size,
  )
}

///|
async fn restore_terminal(tty : @tty.Tty) -> Unit {
  tty.reset_top_bottom_margins()
  tty.reset_style()
  tty.show_cursor()
}

///|
fn exit_newline_count(editor : Editor) -> Int {
  input_text_rows - editor_cursor_row(editor) + 1
}

///|
async fn leave_agent(
  tty : @tty.Tty,
  editor : Editor,
  viewport_top : Int?,
) -> Unit {
  restore_terminal(tty)
  match viewport_top {
    Some(top) => {
      tty.set_cursor_position(viewport_bottom(top), 1)
      write(tty, "\r\n")
    }
    None =>
      for _ in 0..<exit_newline_count(editor) {
        write(tty, "\r\n")
      }
  }
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
async fn redraw_input(
  tty : @tty.Tty,
  viewport_top : Int?,
  old_editor : Editor,
  editor : Editor,
  status : String,
  size : AgentSize,
) -> Int? {
  match viewport_top {
    Some(top) => {
      let top = clamp_viewport_top(top, size)
      redraw_input_at_top(tty, top, editor, status, size)
      Some(top)
    }
    None => {
      redraw_input_from(tty, old_editor, editor, status, size)
      None
    }
  }
}

///|
async fn detect_viewport_top(
  tty : @tty.Tty,
  editor : Editor,
  size : AgentSize,
) -> Int? {
  try tty.query_cursor_position(timeout_ms=esc_timeout_ms) catch {
    _ => None
  } noraise {
    Some(position) =>
      Some(
        clamp_viewport_top(viewport_top_from_cursor(position.row, editor), size),
      )
    None => None
  }
}

///|
async fn read_terminal_events(
  tty : @tty.Tty,
  events : @aqueue.Queue[AgentEvent],
) -> Unit {
  while true {
    let event = tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => {
        events.put(TerminalClosed)
        return
      }
      error => raise error
    }
    events.put(Terminal(event))
  }
}

///|
fn schedule_queued_input(
  group : @async.TaskGroup[Unit],
  events : @aqueue.Queue[AgentEvent],
  input : String,
  shell_mode : Bool,
) -> Unit {
  group.spawn_bg(no_wait=true) <| () => {
    @async.sleep(queued_submit_delay_ms)
    events.put(QueuedInput(text=input, shell_mode~))
  }
}

///|
fn schedule_shell_command(
  group : @async.TaskGroup[Unit],
  events : @aqueue.Queue[AgentEvent],
  command : String,
) -> Unit {
  group.spawn_bg(no_wait=true) <| () => {
    let event = try {
      let (process_stdin, process_stdin_write) = @process.write_to_process()
      process_stdin_write.close()
      let (exit_code, output) = @process.collect_output_merged(
        shell_program(),
        shell_args(command),
        stdin=process_stdin,
      )
      let output = output.text() catch {
        _ => "<non-UTF-8 output: \{output.binary().length()} bytes>"
      }
      ShellResult(command~, exit_code~, output~)
    } catch {
      error =>
        ShellResult(
          command~,
          exit_code=-1,
          output="failed to execute shell: \{error}",
        )
    }
    events.put(event)
  }
}

///|
async fn append_user_turn(
  tty : @tty.Tty,
  cursor_editor : Editor,
  text : String,
  editor : Editor,
  status : String,
  size : AgentSize,
  viewport_top : Int?,
) -> Int? {
  match viewport_top {
    Some(top) => {
      let top = clamp_viewport_top(top, size)
      let top = append_user_above_viewport(tty, top, text, editor, status, size)
      Some(top)
    }
    None => {
      append_user(tty, cursor_editor, text, editor, status, size)
      None
    }
  }
}

///|
async fn append_shell_result(
  tty : @tty.Tty,
  command : String,
  exit_code : Int,
  output : String,
  editor : Editor,
  viewport_top : Int?,
) -> Int? {
  let size = terminal_size(tty)
  let text = format_shell_result(command, exit_code, output)
  match viewport_top {
    Some(top) => {
      let top = clamp_viewport_top(top, size)
      let top = append_shell_above_viewport(
        tty, top, text, editor, "ready", size,
      )
      Some(top)
    }
    None => {
      append_shell(tty, editor, text, editor, "ready", size)
      None
    }
  }
}

///|
async fn submit_text(
  tty : @tty.Tty,
  group : @async.TaskGroup[Unit],
  events : @aqueue.Queue[AgentEvent],
  text : String,
  shell_mode : Bool,
  cursor_editor : Editor,
  editor : Editor,
  viewport_top : Int?,
) -> Int? {
  if shell_mode {
    let command = shell_command_text(text)
    let display_text = "!\{text}"
    let size = terminal_size(tty)
    let viewport_top = append_user_turn(
      tty, cursor_editor, display_text, editor, "running shell...", size, viewport_top,
    )
    if command.length() == 0 {
      append_shell_result(
        tty, command, 1, "empty shell command", editor, viewport_top,
      )
    } else {
      schedule_shell_command(group, events, command)
      viewport_top
    }
  } else {
    let size = terminal_size(tty)
    let viewport_top = append_user_turn(
      tty, cursor_editor, text, editor, "sending...", size, viewport_top,
    )
    let size = terminal_size(tty)
    match viewport_top {
      Some(top) => {
        let top = append_agent_above_viewport(
          tty,
          top,
          fake_response(text),
          editor,
          "ready",
          size,
        )
        Some(top)
      }
      None => {
        append_agent(tty, editor, fake_response(text), editor, "ready", size)
        None
      }
    }
  }
}

///|
async fn run_agent(tty : @tty.Tty) -> Unit {
  @async.with_task_group() <| group => {
    let events : @aqueue.Queue[AgentEvent] = @aqueue.Queue(
      kind=@aqueue.Unbounded,
    )
    let mut editor = Editor::new()
    let mut size = terminal_size(tty)
    tty.show_cursor()
    render_transcript_at_cursor(
      tty,
      "system",
      @color.BrightBlack,
      "primary-screen agent demo",
      size,
    )
    render_transcript_at_cursor(
      tty,
      "system",
      @color.BrightBlack,
      "Enter send  Tab queue  !cmd shell",
      size,
    )
    render_input_at_cursor(tty, editor, "", size)
    place_input_cursor(tty, editor, size)
    let mut viewport_top = detect_viewport_top(tty, editor, size)
    match viewport_top {
      Some(top) => redraw_input_at_top(tty, top, editor, "", size)
      None => ()
    }
    group.spawn_bg(no_wait=true) <| () => { read_terminal_events(tty, events) }
    let mut done = false
    while !done {
      let agent_event = events.get()
      size = terminal_size(tty)
      match agent_event {
        TerminalClosed => done = true
        QueuedInput(text~, shell_mode~) =>
          viewport_top = submit_text(
            tty, group, events, text, shell_mode, editor, editor, viewport_top,
          )
        ShellResult(command~, exit_code~, output~) =>
          viewport_top = append_shell_result(
            tty, command, exit_code, output, editor, viewport_top,
          )
        Terminal(event) =>
          match event {
            @tty.Input(@tty/input.Key(key)) =>
              match key.code {
                @tty/input.Char('c') if key.modifiers.ctrl() => done = true
                @tty/input.Char('d') if key.modifiers.ctrl() &&
                  editor.text.length() == 0 => done = true
                @tty/input.Enter =>
                  if editor.text.length() > 0 || editor.shell_mode {
                    let old_editor = editor
                    let text = editor.text
                    let shell_mode = editor.shell_mode
                    editor = Editor::new()
                    viewport_top = submit_text(
                      tty, group, events, text, shell_mode, old_editor, editor, viewport_top,
                    )
                  } else {
                    viewport_top = redraw_input(
                      tty, viewport_top, editor, editor, "empty input", size,
                    )
                  }
                @tty/input.Tab =>
                  if editor.text.length() > 0 || editor.shell_mode {
                    let old_editor = editor
                    let text = editor.text
                    let shell_mode = editor.shell_mode
                    editor = Editor::new()
                    schedule_queued_input(group, events, text, shell_mode)
                    viewport_top = redraw_input(
                      tty, viewport_top, old_editor, editor, "queued input", size,
                    )
                  } else {
                    viewport_top = redraw_input(
                      tty, viewport_top, editor, editor, "empty input", size,
                    )
                  }
                @tty/input.Up => {
                  let old_editor = editor
                  editor = editor.move_vertical(-1)
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Down => {
                  let old_editor = editor
                  editor = editor.move_vertical(1)
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Left => {
                  let old_editor = editor
                  editor = editor.move_left()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Right => {
                  let old_editor = editor
                  editor = editor.move_right()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Home => {
                  let old_editor = editor
                  editor = editor.move_home()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.End => {
                  let old_editor = editor
                  editor = editor.move_end()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                _ if is_newline_key(key) => {
                  let old_editor = editor
                  editor = editor.insert("\n")
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Backspace => {
                  let old_editor = editor
                  editor = editor.delete_before()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                @tty/input.Delete => {
                  let old_editor = editor
                  editor = editor.delete_after()
                  viewport_top = redraw_input(
                    tty, viewport_top, old_editor, editor, "", size,
                  )
                }
                _ =>
                  match text_from_key(key) {
                    Some(text) => {
                      let old_editor = editor
                      editor = editor.insert_user_text(text)
                      viewport_top = redraw_input(
                        tty, viewport_top, old_editor, editor, "", size,
                      )
                    }
                    None =>
                      viewport_top = redraw_input(
                        tty, viewport_top, editor, editor, "ignored key", size,
                      )
                  }
              }
            @tty.Input(@tty/input.Unknown(bytes)) =>
              viewport_top = redraw_input(
                tty,
                viewport_top,
                editor,
                editor,
                "unknown input: \{bytes.length()} bytes",
                size,
              )
            @tty.Input(@tty/input.Paste(text)) => {
              let old_editor = editor
              editor = editor.insert_user_text(text)
              viewport_top = redraw_input(
                tty, viewport_top, old_editor, editor, "", size,
              )
            }
            @tty.Input(@tty/input.Mouse(_)) => ()
            @tty.Resize(_) =>
              viewport_top = redraw_input(
                tty, viewport_top, editor, editor, "", size,
              )
          }
      }
    }
    leave_agent(tty, editor, viewport_top)
  }
}

///|
async fn main {
  let tty = @tty.Tty::open()
  try tty.with_raw_mode(() => run_agent(tty)) catch {
    error => {
      restore_terminal(tty)
      tty.close()
      raise error
    }
  } noraise {
    _ => {
      tty.close()
      ()
    }
  }
}
