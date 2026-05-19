///|
enum Input {
  File(@async/fs.File)
  Stdio(@async/stdio.Input)
}

///|
pub let stdin : Input = Stdio(@async/stdio.stdin)

///|
pub fn Input::fd(self : Input) -> @async/types.Fd {
  match self {
    File(file) => file.fd()
    Stdio(stdin) => stdin.fd()
  }
}

///|
pub fn Input::close(self : Input) -> Unit {
  match self {
    File(file) => file.close()
    Stdio(_) => ()
  }
}

///|
pub async fn Input::read(
  self : Input,
  buf : FixedArray[Byte],
  offset? : Int,
  max_len? : Int,
) -> Int {
  match self {
    File(file) => file.read(buf, offset?, max_len?)
    Stdio(stdin) => stdin.read(buf, offset?, max_len?)
  }
}

///|
pub async fn Input::read_some(self : Input) -> Bytes? {
  match self {
    File(file) => file.read_some()
    Stdio(stdin) => stdin.read_some()
  }
}

///|
enum Output {
  File(@async/fs.File)
  Stdio(@async/stdio.Output)
}

///|
pub let stdout : Output = Stdio(@async/stdio.stdout)

///|
pub let stderr : Output = Stdio(@async/stdio.stderr)

///|
pub fn Output::fd(self : Self) -> @async/types.Fd {
  match self {
    File(file) => file.fd()
    Stdio(output) => output.fd()
  }
}

///|
pub fn Output::close(self : Output) -> Unit {
  match self {
    File(file) => file.close()
    Stdio(_) => ()
  }
}
