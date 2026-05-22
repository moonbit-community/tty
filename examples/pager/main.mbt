///|
let esc_timeout_ms : Int = 50

///|
priv struct PagerSize {
  rows : Int
  cols : Int
}

///|
priv struct PagerArgs {
  path : String
}

///|
fn pager_command() -> @argparse.Command {
  @argparse.Command(
    "pager",
    about="Page a text file in the terminal primary screen.",
    positionals=[
      @argparse.PositionArg(
        "file",
        about="File to page.",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
    ],
  )
}

///|
fn pager_args_from_matches(matches : @argparse.Matches) -> PagerArgs {
  let path = match matches.values {
    { "file": [path], .. } => path
    _ => abort("examples/pager: argparse did not provide required file")
  }
  { path, }
}

///|
fn parse_args_from(argv : ArrayView[String]) -> PagerArgs raise {
  pager_args_from_matches(pager_command().parse(argv~, env={}))
}

///|
fn parse_cli_args() -> PagerArgs raise {
  let args = @env.args()
  if args.length() > 1 {
    parse_args_from(args[1:])
  } else {
    parse_args_from([])
  }
}

///|
fn clamp(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

///|
fn terminal_size(tty : @tty.Tty) -> PagerSize {
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
fn body_rows(size : PagerSize) -> Int {
  if size.rows <= 1 {
    1
  } else {
    size.rows - 1
  }
}

///|
fn status_row(size : PagerSize) -> Int {
  if size.rows <= 1 {
    1
  } else {
    size.rows
  }
}

///|
fn page_step(size : PagerSize) -> Int {
  let rows = body_rows(size)
  if rows <= 1 {
    1
  } else {
    rows - 1
  }
}

///|
fn max_offset(lines : Array[String], rows : Int) -> Int {
  let value = lines.length() - rows
  if value < 0 {
    0
  } else {
    value
  }
}

///|
fn clamp_offset(offset : Int, lines : Array[String], rows : Int) -> Int {
  clamp(offset, 0, max_offset(lines, rows))
}

///|
fn content_fits(lines : Array[String], size : PagerSize) -> Bool {
  max_offset(lines, body_rows(size)) == 0
}

///|
fn split_lines(text : String) -> Array[String] {
  text
  .replace_all(old="\r\n", new="\n")
  .replace_all(old="\r", new="\n")
  .split("\n")
  .map(line => line.to_owned())
  .collect()
}

///|
async fn load_content(args : PagerArgs) -> (String, Array[String]) {
  (args.path, split_lines(@async/fs.read_file(args.path).text()))
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
fn line_at(lines : Array[String], index : Int) -> String {
  if index < 0 || index >= lines.length() {
    ""
  } else {
    lines[index]
  }
}

///|
async fn render_content_row(
  tty : @tty.Tty,
  row : Int,
  text : String,
  cols : Int,
) -> Unit {
  tty.set_cursor_position(row, 1)
  tty.erase_line_all()
  tty.write(fit_line(text, cols))
}

///|
async fn render_status(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Unit {
  tty.set_cursor_position(status_row(size), 1)
  render_status_current(tty, title, lines, offset, size)
}

///|
async fn render_status_current(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Unit {
  let rows = body_rows(size)
  let first = if lines.length() == 0 { 0 } else { offset + 1 }
  let last = clamp(offset + rows, 0, lines.length())
  let controls = if max_offset(lines, rows) == 0 {
    "all content fits"
  } else {
    "q quit  j/k scroll  space/b page"
  }
  let status = "\{title}  \{first}-\{last}/\{lines.length()}  \{controls}"
  tty.write("\r")
  tty.erase_line_all()
  tty.write(fit_line(status, size.cols))
}

///|
async fn write_inline_content_row(
  tty : @tty.Tty,
  text : String,
  cols : Int,
) -> Unit {
  tty.write(fit_line(text, cols))
  tty.write("\r\n")
}

///|
async fn render_initial(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Bool {
  let rows = body_rows(size)
  if content_fits(lines, size) {
    for row in 0..<lines.length() {
      write_inline_content_row(tty, line_at(lines, row), size.cols)
    }
    render_status_current(tty, title, lines, offset, size)
    false
  } else {
    for row in 0..<rows {
      write_inline_content_row(tty, line_at(lines, offset + row), size.cols)
    }
    render_status_current(tty, title, lines, offset, size)
    tty.set_top_bottom_margins(1, rows)
    tty.set_cursor_position(status_row(size), 1)
    render_status_current(tty, title, lines, offset, size)
    true
  }
}

///|
async fn render_full(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Unit {
  let rows = body_rows(size)
  tty.set_top_bottom_margins(1, rows)
  for row in 1..<=rows {
    render_content_row(tty, row, line_at(lines, offset + row - 1), size.cols)
  }
  render_status(tty, title, lines, offset, size)
}

///|
async fn scroll_forward_one(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Unit {
  let rows = body_rows(size)
  tty.set_top_bottom_margins(1, rows)
  tty.set_cursor_position(rows, 1)
  tty.write("\n")
  render_content_row(tty, rows, line_at(lines, offset + rows - 1), size.cols)
  render_status(tty, title, lines, offset, size)
}

///|
async fn scroll_backward_one(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  offset : Int,
  size : PagerSize,
) -> Unit {
  let rows = body_rows(size)
  tty.set_top_bottom_margins(1, rows)
  tty.set_cursor_position(1, 1)
  tty.reverse_index()
  render_content_row(tty, 1, line_at(lines, offset), size.cols)
  render_status(tty, title, lines, offset, size)
}

///|
fn size_changed(a : PagerSize, b : PagerSize) -> Bool {
  a.rows != b.rows || a.cols != b.cols
}

///|
async fn redraw(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
  old_offset : Int,
  new_offset : Int,
  old_size : PagerSize,
  new_size : PagerSize,
) -> Unit {
  if size_changed(old_size, new_size) {
    render_full(tty, title, lines, new_offset, new_size)
  } else if new_offset == old_offset + 1 {
    scroll_forward_one(tty, title, lines, new_offset, new_size)
  } else if new_offset == old_offset - 1 {
    scroll_backward_one(tty, title, lines, new_offset, new_size)
  } else if new_offset != old_offset {
    render_full(tty, title, lines, new_offset, new_size)
  } else {
    render_status(tty, title, lines, new_offset, new_size)
  }
}

///|
async fn restore_terminal(tty : @tty.Tty) -> Unit {
  tty.reset_top_bottom_margins()
  tty.show_cursor()
}

///|
async fn leave_pager(tty : @tty.Tty, full_screen : Bool) -> Unit {
  if full_screen {
    let size = terminal_size(tty)
    restore_terminal(tty)
    tty.set_cursor_position(status_row(size), 1)
  } else {
    tty.show_cursor()
  }
  tty.write("\r\n")
}

///|
async fn run_pager(
  tty : @tty.Tty,
  title : String,
  lines : Array[String],
) -> Unit {
  let mut size = terminal_size(tty)
  let mut offset = clamp_offset(0, lines, body_rows(size))
  let mut full_screen = render_initial(tty, title, lines, offset, size)
  while true {
    let event = tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => break
      error => raise error
    }
    let old_offset = offset
    let old_size = size
    let mut next_offset = offset
    let mut quit = false
    match event {
      @tty.Input(input) =>
        match input {
          @tty/input.Key(key) =>
            match key.code {
              Char('q') => quit = true
              Char('c') if key.modifiers.ctrl() => quit = true
              Down | Char('j') => next_offset = offset + 1
              Up | Char('k') => next_offset = offset - 1
              PageDown | Char(' ') => next_offset = offset + page_step(size)
              PageUp | Char('b') => next_offset = offset - page_step(size)
              Home | Char('g') => next_offset = 0
              End | Char('G') =>
                next_offset = max_offset(lines, body_rows(size))
              _ => ()
            }
          Paste(_) => ()
          Unknown(_) => ()
        }
      @tty.Resize(_) => ()
    }
    if quit {
      break
    }
    size = terminal_size(tty)
    next_offset = clamp_offset(next_offset, lines, body_rows(size))
    if full_screen {
      redraw(tty, title, lines, old_offset, next_offset, old_size, size)
    } else if content_fits(lines, size) {
      render_status_current(tty, title, lines, next_offset, size)
    } else {
      full_screen = render_initial(tty, title, lines, next_offset, size)
    }
    offset = next_offset
  }
  leave_pager(tty, full_screen)
}

///|
async fn with_pager_terminal(title : String, lines : Array[String]) -> Unit {
  let tty = @tty.Tty::stdio()
  tty.hide_cursor()
  try tty.with_raw_mode(() => run_pager(tty, title, lines)) catch {
    error => {
      restore_terminal(tty)
      raise error
    }
  } noraise {
    _ => ()
  }
}

///|
async fn main {
  let args = parse_cli_args()
  let (title, lines) = load_content(args)
  with_pager_terminal(title, lines)
}
