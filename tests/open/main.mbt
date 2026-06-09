///|
async fn main {
  let tty = @tty.Tty::open()
  defer tty.close()
  let size = tty.window_size()
  @stdio.stdout.write("open: ok\n")
  @stdio.stdout.write("rows: \{size.rows}\n")
  @stdio.stdout.write("cols: \{size.cols}\n")
  tty.write_string("open-write: ok\n")
}
