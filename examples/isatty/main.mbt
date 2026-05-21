///|
async fn main {
  @stdio.stdout.write("isatty: \{@tty.isatty(@stdio.stdin)}\n")
}
