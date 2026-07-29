///|
/// Input backend of a wasm `Tty`, chosen at runtime: ANSI byte decoding for
/// Unix terminals (and non-terminal inputs anywhere), sidecar-streamed
/// console records on Windows terminals.
priv enum WasmInput {
  Ansi(@input.EventReader)
  Win32Console(@win32.StreamEventReader)
}

///|
/// Coordinated terminal input/output handle.
///
/// `Tty` is for terminal protocols that need to write a request and read the
/// response from the same terminal input stream. It does not model a screen.
struct Tty {
  input : &Reader
  input_fd : @async/types.Fd
  output : &Writer
  output_fd : @async/types.Fd
  backend : WasmInput
  pending_input : Array[@public_input.InputEvent]
  // Serializes output writes so a single `write`/`write_string` call lands on
  // the terminal atomically with respect to other concurrent writers.
  write_lock : @lock.Lock
}

///|
/// Create a coordinated terminal handle from input and output handles.
///
/// On wasm this is `async`: picking the input backend may ask the sidecar
/// whether stdin is a Windows console.
pub async fn[I : Reader, O : Writer] Tty::new(input : I, output : O) -> Tty {
  let input = input as &Reader
  let input_fd = Fd::fd(input)
  let output = output as &Writer
  let output_fd = Fd::fd(output)
  let backend = if host_platform() is Windows &&
    stdio_slot(input_fd) is Some(0) &&
    isatty(@async/stdio.stdin) {
    Win32Console(sidecar().console_event_reader())
  } else {
    Ansi(@input.EventReader::new(input as &@async/io.Reader))
  }
  {
    input,
    input_fd,
    output,
    output_fd,
    backend,
    pending_input: [],
    write_lock: @lock.Lock::new(),
  }
}

///|
/// Wrap process stdio as one coordinated terminal handle.
pub async fn Tty::stdio() -> Tty {
  Tty::new(@async/stdio.stdin, @async/stdio.stdout)
}

///|
/// Close the underlying input and output handles.
///
/// Closing stdio-backed handles is a no-op.
pub fn Tty::close(self : Self) -> Unit {
  match self.backend {
    Win32Console(reader) => reader.close()
    Ansi(_) => ()
  }
  self.input.close()
  self.output.close()
}

///|
async fn Tty::read_resize_event(self : Self) -> Event {
  ignore(self)
  let size = sidecar().wait_resize()
  Resize(size)
}

///|
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  match self.backend {
    Ansi(reader) =>
      @async.with_task_group() <| group => {
        group.spawn_bg(no_wait=true) <| () => {
          group.return_immediately(
            read_decoded_input_event(reader, esc_timeout_ms),
          )
        }
        self.read_resize_event()
      }
    Win32Console(reader) => self.read_console_event(reader, esc_timeout_ms)
  }
}

///|
async fn Tty::read_console_event(
  self : Self,
  reader : @win32.StreamEventReader,
  esc_timeout_ms : Int,
) -> Event {
  for ;; {
    match reader.read_event(esc_timeout_ms~) {
      Some(Input(event)) => return Input(event)
      Some(Resize) =>
        try self.window_size() catch {
          _ => ()
        } noraise {
          size => return Resize(size)
        }
      None => fail("Windows console input reader closed")
    }
  }
}

///|
async fn Tty::read_internal_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> @input.Event {
  match self.backend {
    Ansi(reader) => reader.read_event(esc_timeout_ms~)
    Win32Console(reader) => reader.read_internal_event(esc_timeout_ms~)
  }
}
