///|
test "ffmpeg frame arguments" {
  inspect(
    ffmpeg_frame_args("/tmp/bad apple.mp4", "/tmp/demo").join("|"),
    content="-hide_banner|-loglevel|error|-y|-i|/tmp/bad apple.mp4|-vf|fps=12,scale=512:-1:flags=lanczos,scale=iw:trunc(ih*0.85/2)*2:flags=lanczos|/tmp/demo/frames/frame-%05d.png",
  )
}

///|
test "magick sixel arguments" {
  inspect(
    magick_sixel_args("/tmp/demo/frames/frame-00001.png").join("|"),
    content="/tmp/demo/frames/frame-00001.png|sixel:-",
  )
}

///|
test "support and mode labels" {
  inspect(support_label(true, false), content="Kitty graphics: on | Sixel: off")
  inspect(support_label(false, true), content="Kitty graphics: off | Sixel: on")
  inspect(
    support_label(false, false),
    content="Kitty graphics: off | Sixel: off",
  )
  inspect(mode_label(graphics_mode(true, true)), content="mode: Kitty graphics")
  inspect(mode_label(graphics_mode(false, true)), content="mode: Sixel")
  inspect(mode_label(graphics_mode(false, false)), content="mode: unavailable")
}

///|
test "frame placement respects available cells" {
  let roomy = frame_placement(30, 100)
  inspect("\{roomy.columns}x\{roomy.rows}", content="64x20")
  let small = frame_placement(10, 40)
  inspect("\{small.columns}x\{small.rows}", content="40x4")
  let tiny = frame_placement(4, 0)
  inspect("\{tiny.columns}x\{tiny.rows}", content="1x1")
}

///|
test "ctrl c exits" {
  inspect(
    is_exit_key(
      @tty/input.KeyEvent::new(
        Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
    content="true",
  )
  inspect(is_exit_key(@tty/input.KeyEvent::new(Char('q'))), content="false")
  inspect(
    is_exit_key(
      @tty/input.KeyEvent::new(
        Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
        kind=Release,
      ),
    ),
    content="false",
  )
}
