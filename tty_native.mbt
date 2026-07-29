///|
/// Coordinated terminal input/output handle.
///
/// `Tty` is for terminal protocols that need to write a request and read the
/// response from the same terminal input stream. It does not model a screen.
#cfg(platform="windows")
struct Tty {
  input : &Reader
  input_fd : @async/types.Fd
  output : &Writer
  output_fd : @async/types.Fd
  input_backend : WindowsInput
  pending_input : Array[@public_input.InputEvent]
  // Serializes output writes so a single `write`/`write_string` call lands on
  // the terminal atomically with respect to other concurrent writers.
  write_lock : @lock.Lock
}

///|
#cfg(not(platform="windows"))
struct Tty {
  input : &Reader
  input_fd : @async/types.Fd
  output : &Writer
  output_fd : @async/types.Fd
  reader : @input.EventReader
  pending_input : Array[@public_input.InputEvent]
  // Serializes output writes so a single `write`/`write_string` call lands on
  // the terminal atomically with respect to other concurrent writers.
  write_lock : @lock.Lock
}

///|
/// Create a coordinated terminal handle from input and output handles.
#cfg(platform="windows")
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty raise {
  let input = input as &Reader
  let input_fd = input.fd()
  let output = output as &Writer
  let output_fd = output.fd()
  let input_backend = WindowsInput::new(input_fd, input as &@async/io.Reader)
  {
    input,
    input_fd,
    output,
    output_fd,
    input_backend,
    pending_input: [],
    write_lock: @lock.Lock::new(),
  }
}

///|
/// Create a coordinated terminal handle from input and output handles.
#cfg(not(platform="windows"))
pub fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty raise {
  let input = input as &Reader
  let input_fd = Fd::fd(input)
  let output = output as &Writer
  let output_fd = Fd::fd(output)
  {
    input,
    input_fd,
    output,
    output_fd,
    reader: @input.EventReader::new(input as &@async/io.Reader),
    pending_input: [],
    write_lock: @lock.Lock::new(),
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub fn Tty::stdio() -> Tty raise {
  Tty::new(@async/stdio.stdin, @async/stdio.stdout)
}

///|
/// Close the underlying input and output handles.
///
/// Closing stdio-backed handles is a no-op.
#cfg(platform="windows")
pub fn Tty::close(self : Self) -> Unit {
  self.input_backend.close()
  self.input.close()
  self.output.close()
}

///|
/// Close the underlying input and output handles.
///
/// Closing stdio-backed handles is a no-op.
#cfg(not(platform="windows"))
pub fn Tty::close(self : Self) -> Unit {
  self.input.close()
  self.output.close()
}
