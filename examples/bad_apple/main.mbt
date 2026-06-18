///|
const DefaultVideoPath : String = "/Users/haoxiang/Downloads/bad-apple.mp4"

///|
const EscTimeoutMs : Int = 50

///|
const FramesPerSecond : Int = 12

///|
const FrameIntervalMs : Int = 1000 / FramesPerSecond

///|
const FrameTopRow : Int = 7

///|
const MaxFrameColumns : Int = 64

///|
const MaxFrameRows : Int = 20

///|
const FramePixelWidth : Int = 512

///|
const KittyImageId : Int = 424242

///|
priv struct ProcessResult {
  code : Int
  output : String
}

///|
priv struct BinaryProcessResult {
  code : Int
  stdout : Bytes
  stderr : String
}

///|
priv struct PlaybackControl {
  mut stop_requested : Bool
}

///|
priv struct FramePlacement {
  columns : Int
  rows : Int
}

///|
priv enum GraphicsMode {
  KittyGraphics
  SixelGraphics
  NoGraphics
} derive(Eq)

///|
priv enum PrepareOutcome {
  Prepared(tmp_dir~ : String, frames~ : Array[String])
  PrepareFailed(String)
}

///|
priv enum SixelOutcome {
  ConvertedSixel(Bytes)
  SixelFailed(String)
}

///|
fn frames_dir(tmp_dir : String) -> String {
  tmp_dir + "/frames"
}

///|
fn frame_pattern(tmp_dir : String) -> String {
  frames_dir(tmp_dir) + "/frame-%05d.png"
}

///|
fn ffmpeg_frame_args(video_path : String, tmp_dir : String) -> Array[String] {
  [
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    "-i",
    video_path,
    "-vf",
    "fps=\{FramesPerSecond},scale=\{FramePixelWidth}:-1:flags=lanczos,scale=iw:trunc(ih*0.85/2)*2:flags=lanczos",
    frame_pattern(tmp_dir),
  ]
}

///|
fn magick_sixel_args(path : String) -> Array[String] {
  [path, "sixel:-"]
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
async fn run_binary_tool(
  command : StringView,
  args : Array[String],
  cwd? : StringView,
) -> BinaryProcessResult {
  @async.with_task_group(group => {
    let (stdout_reader, stdout_writer) = @pipe.pipe()
    let (stderr_reader, stderr_writer) = @pipe.pipe()
    defer stdout_reader.close()
    defer stderr_reader.close()
    let process = @process.spawn(
      group,
      command,
      args,
      stdout=stdout_writer,
      stderr=stderr_writer,
      cwd?,
    )
    stdout_writer.close()
    stderr_writer.close()
    let stdout = stdout_reader.read_all().binary()
    let stderr = stderr_reader.read_all().text()
    let code = process.wait()
    { code, stdout, stderr }
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
async fn try_run_binary_tool(
  command : StringView,
  args : Array[String],
  cwd? : StringView,
) -> BinaryProcessResult? {
  Some(run_binary_tool(command, args, cwd?)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
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
async fn prepare_frames(video_path : String) -> PrepareOutcome {
  if !@fs.exists(video_path) {
    return PrepareFailed("video not found: " + video_path)
  }
  let tmp_dir = @fs.tmpdir(prefix="tty-bad-apple-") catch {
    error if @async.is_being_cancelled() => raise error
    _ => return PrepareFailed("failed to create a temporary frame directory")
  }
  try {
    @fs.mkdir(frames_dir(tmp_dir))
    match
      try_run_tool(
        "ffmpeg",
        ffmpeg_frame_args(video_path, tmp_dir),
        cwd=tmp_dir,
      ) {
      Some(result) =>
        if result.code == 0 {
          let frames = frame_paths(tmp_dir)
          if frames.length() == 0 {
            cleanup_tmp_dir(tmp_dir)
            PrepareFailed("ffmpeg produced no frames")
          } else {
            Prepared(tmp_dir~, frames~)
          }
        } else {
          cleanup_tmp_dir(tmp_dir)
          PrepareFailed("ffmpeg failed:\n" + summarize_output(result.output))
        }
      None => {
        cleanup_tmp_dir(tmp_dir)
        PrepareFailed(
          "failed to run ffmpeg. Install ffmpeg or make sure it is on PATH.",
        )
      }
    }
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => {
      cleanup_tmp_dir(tmp_dir)
      PrepareFailed("failed to prepare video frames")
    }
  }
}

///|
async fn frame_paths(tmp_dir : String) -> Array[String] {
  let names = @fs.readdir(frames_dir(tmp_dir), sort=true)
  let paths : Array[String] = []
  for name in names {
    paths.push(frames_dir(tmp_dir) + "/" + name)
  }
  paths
}

///|
async fn convert_png_to_sixel(path : String) -> SixelOutcome {
  match try_run_binary_tool("magick", magick_sixel_args(path)) {
    Some(result) =>
      if result.code == 0 && result.stdout.length() > 0 {
        ConvertedSixel(result.stdout)
      } else {
        SixelFailed(
          "magick sixel conversion failed:\n" + summarize_output(result.stderr),
        )
      }
    None =>
      SixelFailed(
        "failed to run magick for Sixel conversion. Install ImageMagick or make sure magick is on PATH.",
      )
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
fn graphics_mode(
  kitty_graphics_supported : Bool,
  sixel_graphics_supported : Bool,
) -> GraphicsMode {
  if kitty_graphics_supported {
    KittyGraphics
  } else if sixel_graphics_supported {
    SixelGraphics
  } else {
    NoGraphics
  }
}

///|
fn support_label(
  kitty_graphics_supported : Bool,
  sixel_graphics_supported : Bool,
) -> String {
  if kitty_graphics_supported {
    if sixel_graphics_supported {
      "Kitty graphics: on | Sixel: on"
    } else {
      "Kitty graphics: on | Sixel: off"
    }
  } else if sixel_graphics_supported {
    "Kitty graphics: off | Sixel: on"
  } else {
    "Kitty graphics: off | Sixel: off"
  }
}

///|
fn mode_label(mode : GraphicsMode) -> String {
  match mode {
    KittyGraphics => "mode: Kitty graphics"
    SixelGraphics => "mode: Sixel"
    NoGraphics => "mode: unavailable"
  }
}

///|
fn frame_text(
  status : String,
  kitty_graphics_supported : Bool,
  sixel_graphics_supported : Bool,
  video_path : String,
  frame_count : Int?,
) -> String {
  let count = match frame_count {
    Some(count) => "\{count}"
    None => "-"
  }
  let mode = graphics_mode(kitty_graphics_supported, sixel_graphics_supported)
  (
    $|bad apple graphics demo
    $|  \{support_label(kitty_graphics_supported, sixel_graphics_supported)}
    $|  \{mode_label(mode)} | frames: \{count} | fps: \{FramesPerSecond}
    $|  Ctrl-C exits
    $|  source: \{clip_text(video_path, 76)}
    $|  status: \{clip_text(status, 900).replace_all(old="\n", new="\n  ")}
    $|
  )
}

///|
async fn draw_status(
  tty : @tty.Tty,
  status : String,
  kitty_graphics_supported : Bool,
  sixel_graphics_supported : Bool,
  video_path : String,
  frame_count : Int?,
) -> Unit {
  let frame = frame_text(
    status, kitty_graphics_supported, sixel_graphics_supported, video_path, frame_count,
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
fn bounded_cell_count(preferred : Int, available : Int) -> Int {
  if available <= 0 {
    1
  } else if preferred < available {
    preferred
  } else {
    available
  }
}

///|
fn frame_placement(rows : Int, cols : Int) -> FramePlacement {
  {
    columns: bounded_cell_count(MaxFrameColumns, cols),
    rows: bounded_cell_count(MaxFrameRows, rows - FrameTopRow + 1),
  }
}

///|
fn current_frame_placement(tty : @tty.Tty) -> FramePlacement {
  try {
    let size = tty.window_size()
    frame_placement(size.rows, size.cols)
  } catch {
    _ => { columns: MaxFrameColumns, rows: MaxFrameRows }
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
async fn read_exit_keys(tty : @tty.Tty, control : PlaybackControl) -> Unit {
  while !control.stop_requested {
    let event = tty.read_event(esc_timeout_ms=EscTimeoutMs) catch {
      error if @async.is_being_cancelled() => raise error
      _ => {
        control.stop_requested = true
        return
      }
    }
    match event {
      Input(Key(key)) =>
        if is_exit_key(key) {
          control.stop_requested = true
          return
        }
      Input(_) | Resize(_) => ()
    }
  }
}

///|
async fn wait_for_exit(control : PlaybackControl) -> Unit {
  while !control.stop_requested {
    @async.sleep(50)
  }
}

///|
async fn draw_frame(
  tty : @tty.Tty,
  mode : GraphicsMode,
  placement : FramePlacement,
  path : String,
) -> String? {
  tty.set_cursor_position(FrameTopRow, 1)
  match mode {
    KittyGraphics => {
      let png = @fs.read_file(path).binary()
      tty.display_kitty_png(
        png,
        image_id=KittyImageId,
        columns=placement.columns,
        rows=placement.rows,
      )
      None
    }
    SixelGraphics =>
      match convert_png_to_sixel(path) {
        ConvertedSixel(sixel) => {
          tty.display_sixel(sixel)
          None
        }
        SixelFailed(message) => Some(message)
      }
    NoGraphics => Some("terminal graphics are not available")
  }
}

///|
async fn play_frames(
  tty : @tty.Tty,
  control : PlaybackControl,
  mode : GraphicsMode,
  frames : Array[String],
) -> String {
  let placement = current_frame_placement(tty)
  let start_ms = @async.now()
  for index, path in frames {
    if control.stop_requested {
      return "Stopped."
    }
    match draw_frame(tty, mode, placement, path) {
      Some(message) => return message
      None => ()
    }
    let target_ms = start_ms +
      (index + 1).to_int64() * FrameIntervalMs.to_int64()
    let delay_ms = target_ms - @async.now()
    if delay_ms > 0 {
      @async.sleep(delay_ms.to_int())
    }
  }
  "Finished. Ctrl-C exits."
}

///|
async fn run_bad_apple_demo(tty : @tty.Tty) -> Unit {
  let kitty_graphics_supported = tty.query_kitty_graphics_support(
    timeout_ms=100,
  )
  let sixel_graphics_supported = tty.query_sixel_graphics_support(
    timeout_ms=100,
  )
  let mode = graphics_mode(kitty_graphics_supported, sixel_graphics_supported)
  let mut tmp_dir : String? = None
  try
    @async.with_task_group() <| group => {
      let control = { stop_requested: false }
      group.spawn_bg(no_wait=true) <| () => { read_exit_keys(tty, control) }
      if mode == NoGraphics {
        draw_status(
          tty,
          "Terminal graphics are not available.",
          kitty_graphics_supported,
          sixel_graphics_supported,
          DefaultVideoPath,
          None,
        )
        wait_for_exit(control)
      } else {
        draw_status(
          tty,
          "Preparing frames with ffmpeg...",
          kitty_graphics_supported,
          sixel_graphics_supported,
          DefaultVideoPath,
          None,
        )
        match prepare_frames(DefaultVideoPath) {
          Prepared(tmp_dir=prepared_tmp_dir, frames~) => {
            tmp_dir = Some(prepared_tmp_dir)
            if !control.stop_requested {
              draw_status(
                tty,
                "Playing...",
                kitty_graphics_supported,
                sixel_graphics_supported,
                DefaultVideoPath,
                Some(frames.length()),
              )
              let status = play_frames(tty, control, mode, frames)
              draw_status(
                tty,
                status,
                kitty_graphics_supported,
                sixel_graphics_supported,
                DefaultVideoPath,
                Some(frames.length()),
              )
            }
            wait_for_exit(control)
          }
          PrepareFailed(message) => {
            draw_status(
              tty,
              message,
              kitty_graphics_supported,
              sixel_graphics_supported,
              DefaultVideoPath,
              None,
            )
            wait_for_exit(control)
          }
        }
      }
    }
  catch {
    error => {
      cleanup_render(tmp_dir)
      raise error
    }
  }
  cleanup_render(tmp_dir)
}

///|
async fn cleanup_render(tmp_dir : String?) -> Unit {
  match tmp_dir {
    Some(tmp_dir) => cleanup_tmp_dir(tmp_dir)
    None => ()
  }
}

///|
async fn[T] with_bad_apple_screen(tty : @tty.Tty, f : async () -> T) -> T {
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
  with_bad_apple_screen(tty, () => {
    tty.with_raw_mode(() => run_bad_apple_demo(tty))
  })
}
