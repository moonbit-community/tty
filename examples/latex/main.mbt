///|
const EscTimeoutMs : Int = 50

///|
const ImageTopRow : Int = 13

///|
const ImageColumns : Int = 40

///|
const ImageRows : Int = 8

///|
priv struct ProcessResult {
  code : Int
  output : String
}

///|
priv enum RenderOutcome {
  Rendered(tmp_dir~ : String, path~ : String, png~ : Bytes)
  RenderFailed(String)
}

///|
fn latex_document(formula : String) -> String {
  let prefix =
    #|\documentclass[preview,border=8pt]{standalone}
    #|\usepackage{amsmath}
    #|\usepackage{amssymb}
    #|\begin{document}
    #|
  let suffix =
    #|$
    #|\end{document}
    #|
  prefix + "$\\displaystyle " + formula + suffix
}

///|
fn tex_path(tmp_dir : String) -> String {
  tmp_dir + "/formula.tex"
}

///|
fn pdf_path(tmp_dir : String) -> String {
  tmp_dir + "/formula.pdf"
}

///|
fn png_prefix(tmp_dir : String) -> String {
  tmp_dir + "/formula"
}

///|
fn png_path(tmp_dir : String) -> String {
  tmp_dir + "/formula.png"
}

///|
fn tectonic_args(tmp_dir : String) -> Array[String] {
  ["--outdir", tmp_dir, tex_path(tmp_dir)]
}

///|
fn pdflatex_args(tmp_dir : String) -> Array[String] {
  [
    "-interaction=nonstopmode",
    "-halt-on-error",
    "-output-directory",
    tmp_dir,
    tex_path(tmp_dir),
  ]
}

///|
fn pdftocairo_args(tmp_dir : String) -> Array[String] {
  ["-png", "-singlefile", "-r", "180", pdf_path(tmp_dir), png_prefix(tmp_dir)]
}

///|
async fn run_tool(
  command : StringView,
  args : Array[String],
  cwd? : StringView,
) -> ProcessResult {
  @async.with_task_group(group => {
    let (reader, writer) = @pipe.pipe()
    defer reader.close()
    let process = @process.spawn(
      group,
      command,
      args,
      stdout=writer,
      stderr=writer,
      cwd?,
    )
    writer.close()
    let output = reader.read_all().text()
    let code = process.wait()
    { code, output }
  })
}

///|
async fn try_run_tool(
  command : StringView,
  args : Array[String],
  cwd? : StringView,
) -> ProcessResult? {
  Some(run_tool(command, args, cwd?)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
async fn compile_pdf(tmp_dir : String) -> String? {
  match try_run_tool("tectonic", tectonic_args(tmp_dir), cwd=tmp_dir) {
    Some(tectonic) =>
      if tectonic.code == 0 {
        None
      } else {
        Some("tectonic failed:\n" + summarize_output(tectonic.output))
      }
    None =>
      match try_run_tool("pdflatex", pdflatex_args(tmp_dir), cwd=tmp_dir) {
        Some(pdflatex) =>
          if pdflatex.code == 0 {
            None
          } else {
            Some(
              "pdflatex fallback failed:\n" + summarize_output(pdflatex.output),
            )
          }
        None =>
          Some(
            "failed to run tectonic or pdflatex. Install tectonic or make sure pdflatex is on PATH.",
          )
      }
  }
}

///|
async fn convert_pdf_to_png(tmp_dir : String) -> String? {
  match try_run_tool("pdftocairo", pdftocairo_args(tmp_dir), cwd=tmp_dir) {
    Some(converter) =>
      if converter.code == 0 {
        None
      } else {
        Some("pdftocairo failed:\n" + summarize_output(converter.output))
      }
    None =>
      Some(
        "failed to run pdftocairo. Install poppler or make sure pdftocairo is on PATH.",
      )
  }
}

///|
async fn cleanup_tmp_dir(tmp_dir : String) -> Unit {
  @fs.rmdir(tmp_dir, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
async fn render_formula(formula : String) -> RenderOutcome {
  try {
    let tmp_dir = @fs.tmpdir(prefix="tty-latex-")
    render_formula_in_dir(tmp_dir, formula)
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => RenderFailed("failed to create a temporary render directory")
  }
}

///|
async fn render_formula_in_dir(
  tmp_dir : String,
  formula : String,
) -> RenderOutcome {
  try {
    @fs.write_file(
      tex_path(tmp_dir),
      latex_document(formula),
      create_mode=CreateOrTruncate,
    )
    match compile_pdf(tmp_dir) {
      Some(message) => {
        cleanup_tmp_dir(tmp_dir)
        return RenderFailed(message)
      }
      None => ()
    }
    match convert_pdf_to_png(tmp_dir) {
      Some(message) => {
        cleanup_tmp_dir(tmp_dir)
        return RenderFailed(message)
      }
      None => ()
    }
    let path = png_path(tmp_dir)
    let png = @fs.read_file(path).binary()
    Rendered(tmp_dir~, path~, png~)
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      cleanup_tmp_dir(tmp_dir)
      RenderFailed("failed to render the formula")
    }
  }
}

///|
fn summarize_output(output : String) -> String {
  let trimmed = output.trim()
  if trimmed == "" {
    "(no output)"
  } else {
    clip_text(trimmed.to_owned(), 900)
  }
}

///|
fn clip_text(text : String, max_chars : Int) -> String {
  if max_chars <= 0 {
    ""
  } else {
    let builder = StringBuilder()
    let mut count = 0
    for char in text {
      if count >= max_chars {
        builder.write_string("...")
        break
      }
      builder.write_char(char)
      count += 1
    }
    builder.to_string()
  }
}

///|
fn is_exit_key(key : @tty/input.KeyEvent) -> Bool {
  match key.kind {
    Release => false
    Press | Repeat =>
      key.modifiers.ctrl() &&
      (match key.code {
        Char('c') => true
        _ => false
      })
  }
}

///|
fn apply_text_key(parts : Array[String], key : @tty/input.KeyEvent) -> Bool {
  match key.kind {
    Release => false
    Press | Repeat =>
      match key.code {
        Backspace =>
          if parts.length() > 0 {
            ignore(parts.remove(parts.length() - 1))
            true
          } else {
            false
          }
        _ =>
          match key.text {
            Some(text) => {
              parts.push(text)
              true
            }
            None => false
          }
      }
  }
}

///|
fn formula_text(parts : Array[String]) -> String {
  parts.join("")
}

///|
fn support_label(kitty_graphics_supported : Bool) -> String {
  if kitty_graphics_supported {
    "Kitty graphics: on"
  } else {
    "Kitty graphics: off"
  }
}

///|
fn rendered_path_label(path : String?) -> String {
  match path {
    Some(path) => "PNG: " + path + "\n"
    None => ""
  }
}

///|
fn frame_text(
  formula : String,
  status : String,
  kitty_graphics_supported : Bool,
  rendered_path : String?,
) -> String {
  let shown_formula = if formula == "" { "E = mc^2" } else { formula }
  (
    $|latex display demo
    $|  \{support_label(kitty_graphics_supported)}
    $|  Ctrl-C exits
    $|
    $|formula:
    $|  \{clip_text(shown_formula, 76)}
    $|
    $|status:
    $|  \{clip_text(status, 900).replace_all(old="\n", new="\n  ")}
    $|\{rendered_path_label(rendered_path)}
    $|
    $|
    $|
  )
}

///|
async fn draw_frame(
  tty : @tty.Tty,
  formula : String,
  status : String,
  kitty_graphics_supported : Bool,
  rendered_path : String?,
) -> Unit {
  let frame = frame_text(
    formula, status, kitty_graphics_supported, rendered_path,
  ).replace_all(old="\n", new="\r\n")
  tty.execute([
    BeginSynchronizedUpdate,
    CursorPosition(1, 1),
    EraseDisplay,
    Print(frame),
    EndSynchronizedUpdate,
  ])
}

///|
async fn draw_png(tty : @tty.Tty, png : Bytes) -> Unit {
  tty.set_cursor_position(ImageTopRow, 1)
  tty.display_kitty_png(png, columns=ImageColumns, rows=ImageRows)
}

///|
async fn cleanup_render(tmp_dir : String?) -> Unit {
  match tmp_dir {
    Some(tmp_dir) => cleanup_tmp_dir(tmp_dir)
    None => ()
  }
}

///|
async fn run_latex_demo(tty : @tty.Tty) -> Unit {
  let kitty_graphics_supported = tty.query_kitty_graphics_support(
    timeout_ms=100,
  )
  let parts : Array[String] = []
  let mut status = "Enter a LaTeX formula and press Enter."
  let mut rendered_path : String? = None
  let mut rendered_png : Bytes? = None
  let mut tmp_dir : String? = None
  draw_frame(
    tty,
    formula_text(parts),
    status,
    kitty_graphics_supported,
    rendered_path,
  )
  for ;; {
    let event = tty.read_event(esc_timeout_ms=EscTimeoutMs)
    match event {
      Resize(_) => {
        draw_frame(
          tty,
          formula_text(parts),
          status,
          kitty_graphics_supported,
          rendered_path,
        )
        if kitty_graphics_supported {
          if rendered_png is Some(png) {
            draw_png(tty, png)
          }
        }
      }
      Input(Key(key)) => {
        if is_exit_key(key) {
          cleanup_render(tmp_dir)
          return
        }
        match key.kind {
          Release => ()
          Press | Repeat =>
            match key.code {
              Enter => {
                let formula = formula_text(parts)
                if formula.trim() == "" {
                  status = "Formula is empty."
                  draw_frame(
                    tty, formula, status, kitty_graphics_supported, rendered_path,
                  )
                } else {
                  status = "Rendering..."
                  rendered_path = None
                  rendered_png = None
                  draw_frame(
                    tty, formula, status, kitty_graphics_supported, rendered_path,
                  )
                  match render_formula(formula) {
                    Rendered(tmp_dir=new_tmp_dir, path~, png~) => {
                      cleanup_render(tmp_dir)
                      tmp_dir = Some(new_tmp_dir)
                      rendered_path = Some(path)
                      rendered_png = Some(png)
                      if kitty_graphics_supported {
                        status = "Rendered."
                      } else {
                        status = "Rendered PNG. Terminal graphics are not available."
                      }
                      draw_frame(
                        tty, formula, status, kitty_graphics_supported, rendered_path,
                      )
                      if kitty_graphics_supported {
                        draw_png(tty, png)
                      }
                    }
                    RenderFailed(message) => {
                      cleanup_render(tmp_dir)
                      tmp_dir = None
                      status = message
                      rendered_path = None
                      rendered_png = None
                      draw_frame(
                        tty, formula, status, kitty_graphics_supported, rendered_path,
                      )
                    }
                  }
                }
              }
              _ =>
                if apply_text_key(parts, key) {
                  status = "Editing."
                  rendered_path = None
                  rendered_png = None
                  draw_frame(
                    tty,
                    formula_text(parts),
                    status,
                    kitty_graphics_supported,
                    rendered_path,
                  )
                }
            }
        }
      }
      Input(_) => ()
    }
  }
}

///|
async fn[T] with_latex_screen(tty : @tty.Tty, f : async () -> T) -> T {
  tty.enter_alt_screen()
  tty.hide_cursor()
  try f() catch {
    error => {
      restore_screen(tty)
      raise error
    }
  } noraise {
    value => {
      restore_screen(tty)
      value
    }
  }
}

///|
async fn restore_screen(tty : @tty.Tty) -> Unit {
  tty.show_cursor()
  tty.leave_alt_screen()
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  with_latex_screen(tty, () => tty.with_raw_mode(() => run_latex_demo(tty)))
}
