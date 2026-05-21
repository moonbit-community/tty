///|
test "isatty" {
  debug_inspect(
    @tty.isatty(@async/stdio.stdin),
    content=(
      #|false
    ),
  )
}
