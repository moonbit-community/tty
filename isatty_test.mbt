///|
#cfg(target="native")
test "isatty" {
  debug_inspect(
    @tty.isatty(@async/stdio.stdin),
    content=(
      #|false
    ),
  )
}

///|
/// There is no descriptor kind query on wasm, so `isatty` reports that
/// instead of guessing.
#cfg(target="wasm")
test "isatty is unsupported on wasm" {
  try @tty.isatty(@async/stdio.stdin) catch {
    _ => ()
  } noraise {
    _ => fail("expected isatty to raise on wasm")
  }
}
