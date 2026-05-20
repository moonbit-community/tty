///|
pub async fn Input::open() -> Input {
  File(@async/fs.open("/dev/tty", mode=ReadOnly))
}

///|
pub async fn Output::open() -> Output {
  File(@async/fs.open("/dev/tty", mode=WriteOnly))
}

///|
/// Open the controlling terminal as one coordinated terminal handle.
pub async fn Tty::open() -> Tty {
  let file = @async/fs.open("/dev/tty", mode=ReadWrite)
  Tty::new(file, file)
}
