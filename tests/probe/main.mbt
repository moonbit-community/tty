///|
/// Terminal probe used by the pty smoke test: exercises isatty, window
/// size, raw mode, resize events and input decoding against a real pty,
/// identically on the native and wasm targets.
async fn main {
  let tty = @tty.Tty::stdio()
  println("isatty-stdin: \{@tty.isatty(@async/stdio.stdin)}")
  let size = tty.window_size()
  println("size: \{size.rows}x\{size.cols}")
  tty.with_raw_mode(() => {
    println("raw: on")
    match tty.read_event() {
      Resize(size) => println("resize: \{size.rows}x\{size.cols}")
      Input(_) => println("unexpected-input")
    }
    match tty.read_event() {
      Input(_) => println("input: ok")
      Resize(_) => println("unexpected-resize")
    }
  })
  println("probe-done")
}
