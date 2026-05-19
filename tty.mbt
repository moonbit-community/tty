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
pub async fn Input::read_byte(self : Input) -> Byte {
  match self {
    File(file) => file.read_exactly(1)[0]
    Stdio(stdin) => stdin.read_exactly(1)[0]
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
pub fn Output::fd(self : Output) -> @async/types.Fd {
  match self {
    File(file) => file.fd()
    Stdio(output) => output.fd()
  }
}

///|
pub async fn Output::write(self : Output, data : &@async/io.Data) -> Unit {
  match self {
    File(file) => file.write(data)
    Stdio(stdio) => stdio.write(data)
  }
}

///|
pub fn Output::close(self : Output) -> Unit {
  match self {
    File(file) => file.close()
    Stdio(_) => ()
  }
}
