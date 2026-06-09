///|
async fn main {
  let tty = @tty.Tty::stdio()
  tty.with_raw_mode(() => {
    @stdio.stdout.write("ready\n")
    try @async.with_timeout(5000, () => {
      while true {
        match tty.read_event() {
          Resize(size) => {
            @stdio.stdout.write("resize: rows=\{size.rows} cols=\{size.cols}\n")
            break
          }
          Input(_) => {
            @stdio.stdout.write("armed\n")
            continue
          }
        }
      }
    }) catch {
      _ => @stdio.stdout.write("timeout\n")
    }
  })
}
