///|
/// Open the controlling terminal as one coordinated terminal handle.
///
/// `CONIN$` / `CONOUT$` are console (character) devices. `@async/fs.open`
/// opens them without `FILE_FLAG_OVERLAPPED`, classifies the handles with
/// `GetFileType` and routes their IO through the thread pool, which is what
/// console devices need.
#cfg(platform="windows")
pub async fn Tty::open() -> Tty {
  let input = @async/fs.open("CONIN$", mode=ReadWrite)
  let output = {
    errdefer input.close()
    @async/fs.open("CONOUT$", mode=ReadWrite)
  }
  Tty::new(input, output)
}
