///|
/// Open the controlling terminal (`/dev/tty`) as one coordinated terminal
/// handle. The single bidirectional file is used for both input and output.
#cfg(all(target="native", not(platform="windows")))
pub async fn Tty::open() -> Tty {
  let terminal = @async/fs.open("/dev/tty", mode=ReadWrite)
  Tty::new(terminal, terminal)
}
