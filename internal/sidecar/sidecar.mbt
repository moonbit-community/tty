///|
/// Raised out of a byte read when the sidecar reports a window resize
/// instead of input. The size is already updated when this is raised; the
/// read can simply be retried.
pub suberror Resized derive(Debug)

///|
pub extend Resized with @debug.Debug::{to_repr}

///|
/// The sidecar reported an error of its own.
pub suberror SidecarError {
  SidecarError(String)
} derive(Debug)

///|
pub extend SidecarError with @debug.Debug::{to_repr}

///|
/// A running sidecar process. Reading from it yields the terminal input,
/// VT bytes or raw console records depending on `input_kind`; writing to it
/// writes to the terminal.
#warnings("-14")
struct Sidecar {
  pid : Int32
  to_child : @async/process.WriteToProcess
  from_child : @async/process.ReadFromProcess
  conn : Connection
  read_buf : @async/io.ReaderBuffer
  // A directory holding the executable, deleted once the process is reaped.
  temp_dir : String?
  mut rows : Int32
  mut cols : Int32
  mut kind : InputKind
  mut raw : Bool
  // Input bytes received but not yet handed out by `_direct_read`.
  mut pending : BytesView
  mut closed : Bool
  mut exit : Int32?
}

///|
/// Start the sidecar executable at `path` with `env` added to its
/// environment, and wait for its hello frame. A `temp_dir` holding the
/// executable is removed by `wait`.
#warnings("-14")
pub async fn spawn(
  path : String,
  env~ : Map[String, String] = Map([]),
  temp_dir~ : String? = None,
) -> Sidecar {
  let (child_stdin, to_child) = @async/process.write_to_process()
  let (from_child, child_stdout) = {
    errdefer to_child.close()
    @async/process.read_from_process()
  }
  let pid = {
    errdefer to_child.close()
    errdefer from_child.close()
    defer child_stdout.close()
    @async/process.spawn_orphan(
      path,
      [],
      extra_env=env,
      stdin=child_stdin,
      stdout=child_stdout,
    )
  }
  let conn = Connection::new(from_child, to_child)
  let sidecar = {
    pid,
    to_child,
    from_child,
    conn,
    read_buf: @async/io.ReaderBuffer::new(),
    temp_dir,
    rows: 0,
    cols: 0,
    kind: Bytes,
    raw: false,
    pending: b""[:],
    closed: false,
    exit: None,
  }
  // From here on the child exists and must be reaped on every exit path.
  errdefer {
    sidecar.close()
    ignore(sidecar.wait())
  }
  match conn.read_frame() {
    Some(Hello(version~, rows~, cols~, kind~)) => {
      guard version == 1 else {
        raise ProtocolError("unsupported sidecar protocol version \{version}")
      }
      sidecar.rows = rows
      sidecar.cols = cols
      sidecar.kind = kind
    }
    Some(Error(message)) => raise SidecarError(message)
    Some(_) => raise ProtocolError("sidecar did not start with a hello frame")
    None => raise ProtocolError("sidecar exited before saying hello")
  }
  sidecar
}

///|
pub fn Sidecar::pid(self : Sidecar) -> Int32 {
  self.pid
}

///|
/// Last known terminal size as `(rows, cols)`.
pub fn Sidecar::size(self : Sidecar) -> (Int32, Int32) {
  (self.rows, self.cols)
}

///|
pub fn Sidecar::is_raw(self : Sidecar) -> Bool {
  self.raw
}

///|
/// Whether the bytes read through `@io.Reader` are VT input or raw console
/// records of a fixed size.
pub fn Sidecar::input_kind(self : Sidecar) -> InputKind {
  self.kind
}

///|
/// Next frame from the sidecar with the size bookkeeping applied, `None`
/// once it has exited. Not to be mixed with reads through `@io.Reader`.
pub async fn Sidecar::read_frame(self : Sidecar) -> Frame? {
  let frame = self.conn.read_frame()
  if frame is Some(Resize(rows~, cols~)) {
    self.rows = rows
    self.cols = cols
  }
  frame
}

///|
pub async fn Sidecar::set_raw(self : Sidecar, on : Bool) -> Unit {
  self.conn.set_raw(on)
  self.raw = on
}

///|
/// Close both pipes. The sidecar restores the terminal and exits when its
/// command pipe closes. Safe to call more than once.
pub fn Sidecar::close(self : Sidecar) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.to_child.close()
  self.from_child.close()
}

///|
/// Reap the sidecar process after `close` and remove its temporary
/// directory. The exit status is remembered, so this can be called again.
/// Reaping is not cancellable: a cancelled first call would leave a zombie.
pub async fn Sidecar::wait(self : Sidecar) -> Int32 {
  if self.exit is Some(exit) {
    return exit
  }
  @async.protect_from_cancel(() => {
    let exit = @async/process.wait_pid(self.pid)
    self.exit = Some(exit)
    if self.temp_dir is Some(dir) {
      @async/fs.rmdir(dir, recursive=true) catch {
        _ => ()
      }
    }
    exit
  })
}

///|
pub impl @async/io.Reader for Sidecar with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @async/io.Reader for Sidecar with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  while self.pending.length() == 0 {
    guard self.read_frame() is Some(frame) else { return 0 }
    match frame {
      Input(bytes) | Record(bytes) => self.pending = bytes[:]
      Resize(..) => raise Resized
      Error(message) => raise SidecarError(message)
      Hello(..) => ()
    }
  }
  let n = if max_len < self.pending.length() {
    max_len
  } else {
    self.pending.length()
  }
  buf.blit_from_bytesview(offset, self.pending[:n])
  self.pending = self.pending[n:]
  n
}

///|
pub extend Sidecar with @async/io.Reader::{
  _direct_read,
  _get_internal_buffer,
  read,
  read_some,
  drop,
  read_all,
  read_until,
  read_exactly,
}

///|
pub impl @async/io.Writer for Sidecar with fn write_once(
  self,
  buf,
  offset~,
  len~,
) {
  // One frame per call; the default `write` loops over the rest.
  let len = if len > MAX_WRITE { MAX_WRITE } else { len }
  self.conn.write(buf[offset:offset + len])
  len
}

///|
pub extend Sidecar with @async/io.Writer::{write_once, write, write_reader}
