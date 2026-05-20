///|
/// Terminal input handle.
///
/// A `Reader` is an async byte reader that also exposes the terminal file
/// descriptor used by stateful terminal operations.
pub(open) trait Reader: @async/io.Reader {
  fn fd(Self) -> @async/types.Fd
  fn close(Self) -> Unit
}

///|
/// Terminal output handle.
///
/// A `Writer` is an async byte writer that also exposes the terminal file
/// descriptor used by output-side terminal queries.
pub(open) trait Writer: @async/io.Writer {
  fn fd(Self) -> @async/types.Fd
  fn close(Self) -> Unit
}

///|
pub impl Reader for @async/fs.File with fd(self) {
  @async/fs.File::fd(self)
}

///|
pub impl Reader for @async/fs.File with close(self) {
  @async/fs.File::close(self)
}

///|
pub impl Writer for @async/fs.File with fd(self) {
  @async/fs.File::fd(self)
}

///|
pub impl Writer for @async/fs.File with close(self) {
  @async/fs.File::close(self)
}

///|
pub impl Reader for @async/stdio.Input with fd(self) {
  @async/stdio.Input::fd(self)
}

///|
pub impl Reader for @async/stdio.Input with close(_) {
  ()
}

///|
pub impl Writer for @async/stdio.Output with fd(self) {
  @async/stdio.Output::fd(self)
}

///|
pub impl Writer for @async/stdio.Output with close(_) {
  ()
}

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
pub async fn Output::write_string(self : Output, string : String) -> Unit {
  self.write(string)
}

///|
pub fn Output::close(self : Output) -> Unit {
  match self {
    File(file) => file.close()
    Stdio(_) => ()
  }
}
