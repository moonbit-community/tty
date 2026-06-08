///|
async fn main {
  @stdio.stdout.write("isatty(stdin): \{@tty.isatty(@stdio.stdin)}\n")
  @stdio.stdout.write("isatty(stdout): \{@tty.isatty(@stdio.stdout)}\n")
  @stdio.stdout.write("isatty(stderr): \{@tty.isatty(@stdio.stderr)}\n")
}
