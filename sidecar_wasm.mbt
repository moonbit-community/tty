///|
/// Wasm backend: terminal syscalls are proxied to a native sidecar process
/// spawned with inherited stdio and reached over loopback TCP (see
/// `sidecar/PROTOCOL.md`). One lazily started sidecar serves the whole
/// program; its lifetime is bounded by the connections, so it exits (and
/// restores the terminal) when this process ends for any reason.
priv enum HostPlatform {
  Linux
  MacOS
  Windows
}

///|
#unsafe_skip_stub_check
fn host_platform_code() -> Int = "moonbitlang/async" "runtime/get_platform"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn host_random_fill(buf : FixedArray[Byte], len : Int) -> Int = "moonbitlang/async" "random/fill"

///|
fn host_platform() -> HostPlatform {
  match host_platform_code() {
    0 => Linux
    1 => MacOS
    _ => Windows
  }
}

///|
async fn host_arch(platform : HostPlatform) -> String {
  match platform {
    // arm64 Windows runs x86_64 binaries through emulation.
    Windows => "x86_64"
    Linux | MacOS => {
      let (code, out) = @async/process.collect_stdout("uname", ["-m"])
      guard code == 0 else { fail("uname -m exited with \{code}") }
      let arch = @utf8.decode(out.binary()).trim().to_owned()
      match arch {
        "arm64" | "aarch64" => "aarch64"
        "amd64" | "x86_64" => "x86_64"
        other => other
      }
    }
  }
}

///|
priv struct Sidecar {
  control : @async/socket.Tcp
  events : @sidecar.EventStream
  control_lock : @lock.Lock
  event_lock : @lock.Lock
  mut next_id : UInt
  mut watching : Bool
  mut console_reader : @win32.StreamEventReader?
}

///|
let sidecar_cell : Ref[Sidecar?] = Ref(None)

///|
let sidecar_init_lock : @lock.Lock = @lock.Lock::new()

///|
async fn sidecar() -> Sidecar {
  if sidecar_cell.val is Some(client) {
    return client
  }
  sidecar_init_lock.with_lock(() => {
    if sidecar_cell.val is Some(client) {
      return client
    }
    let client = launch_sidecar()
    sidecar_cell.val = Some(client)
    client
  })
}

///|
fn make_token() -> String raise {
  let raw = FixedArray::make(16, b'\x00')
  if host_random_fill(raw, raw.length()) < 0 {
    @os_error.check_errno("random/fill")
  }
  let digits = b"0123456789abcdef"
  let hex = Buffer(size_hint=2 * raw.length())
  for byte in raw {
    hex.write_byte(digits[byte.to_int() >> 4])
    hex.write_byte(digits[byte.to_int() & 0xF])
  }
  @utf8.decode(hex.contents())
}

///|
async fn launch_sidecar() -> Sidecar {
  let platform = host_platform()
  let arch = host_arch(platform)
  guard sidecar_binary(platform, arch) is Some(binary) else {
    fail(
      "moonbit-community/tty: no sidecar binary embedded for this host; supported: linux/x86_64, macos/aarch64, windows/x86_64",
    )
  }
  let token = make_token()
  let token_bytes = @utf8.encode(token)
  let server = @async/socket.TcpServer(@async/socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let port = server.addr.port()
  let dir = @async/fs.tmpdir(prefix="moonbit-tty-sidecar")
  let path = if platform is Windows {
    dir + "\\tty-sidecar.exe"
  } else {
    dir + "/tty-sidecar"
  }
  // Not `write_file`: its open flags are mistranslated by the wasm host
  // (moonrun) and fail with ENOENT; plain create + write works.
  let file = @async/fs.create(path, permission=0o755)
  file.write(binary)
  file.close()
  @async/fs.chmod(path, 0o755)
  // Orphan by design: the sidecar is a process-global resource owned by no
  // task group; it exits by itself when the connections close.
  ignore(
    @async/process.spawn_orphan(path, ["--port", port.to_string()], extra_env={
      "MOONBIT_TTY_SIDECAR_TOKEN": token,
    }),
  )
  // The sidecar connects control-then-event; identify by accept order and
  // bound the wait so a crashed sidecar cannot hang startup.
  let control = @async.with_timeout(10_000, () => {
    let (conn, _) = server.accept()
    @sidecar.read_handshake(
      conn as &@async/io.Reader,
      magic=@sidecar.MAGIC_CONTROL,
      token=token_bytes,
    )
    conn
  })
  let events = @async.with_timeout(10_000, () => {
    let (conn, _) = server.accept()
    @sidecar.read_handshake(
      conn as &@async/io.Reader,
      magic=@sidecar.MAGIC_EVENT,
      token=token_bytes,
    )
    conn
  }) catch {
    error => {
      control.close()
      raise error
    }
  }
  if !(platform is Windows) {
    remove_sidecar_binary(path, dir)
  }
  let client = Sidecar::{
    control,
    events: EventStream(events as &@async/io.Reader),
    control_lock: @lock.Lock::new(),
    event_lock: @lock.Lock::new(),
    next_id: 1,
    watching: false,
    console_reader: None,
  }
  if !(platform is Windows) {
    client.watch()
  }
  client
}

///|
/// Best-effort removal of the extracted binary once the sidecar runs; the
/// process keeps its image (Unix only — Windows cannot unlink a running
/// executable, its copy stays in the temp dir).
async fn remove_sidecar_binary(path : String, dir : String) -> Unit {
  try {
    @async/fs.remove(path)
    @async/fs.rmdir(dir)
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// One serialized request/response round-trip. The round-trip is protected
/// from cancellation because tearing it mid-read would desync the control
/// connection for every later request; it stays bounded because the sidecar
/// answers immediately and a dead sidecar surfaces as EOF (`ReaderClosed`).
async fn Sidecar::call(
  self : Sidecar,
  request : @sidecar.Request,
) -> @sidecar.Response {
  self.control_lock.with_lock(() => {
    @async.protect_from_cancel(() => {
      let id = self.next_id
      self.next_id += 1
      @async/io.Writer::write(self.control, request.encode(id~))
      @sidecar.Response::read(self.control as &@async/io.Reader, request, id~)
    })
  })
}

///|
/// Enable terminal-event delivery (idempotent): resize notifications on
/// Unix, exclusive console record streaming on Windows.
async fn Sidecar::watch(self : Sidecar) -> Unit {
  if self.watching {
    return
  }
  match self.call(Watch(enable=true)) {
    Acknowledged => self.watching = true
    Error(errno~) => raise @os_error.OSError(errno, context="tty sidecar watch")
    _ => raise @sidecar.ProtocolViolation
  }
}

///|
/// Wait for the next resize notification (Unix). Waiters take turns holding
/// the event lock; `EventStream` keeps partially received frames across
/// cancellation, so a cancelled waiter never tears the stream.
async fn Sidecar::wait_resize(self : Sidecar) -> WindowSize {
  self.event_lock.with_lock(() => {
    for ;; {
      match self.events.next() {
        Resize(rows~, cols~) => return { rows, cols }
        InputRecords(..) => () // Windows-only; never sent on the Unix path
      }
    }
  })
}

///|
/// The console record reader (Windows): a process-wide singleton, because
/// the sidecar streams the one console's records over the one event
/// connection.
async fn Sidecar::console_event_reader(
  self : Sidecar,
) -> @win32.StreamEventReader {
  if self.console_reader is Some(reader) {
    return reader
  }
  self.watch()
  let reader = @win32.StreamEventReader(self.events)
  self.console_reader = Some(reader)
  reader
}

///|
/// Map a host stdio handle to a sidecar terminal slot. Handles other than
/// the process stdio cannot be named across the process boundary.
fn stdio_slot(fd : @async/types.Fd) -> Int? raise {
  if fd == @async/stdio.stdin.fd() {
    Some(0)
  } else if fd == @async/stdio.stdout.fd() {
    Some(1)
  } else if fd == @async/stdio.stderr.fd() {
    Some(2)
  } else {
    None
  }
}

///|
/// Slot used for handles that are not the process stdio: the sidecar
/// rejects it with `EINVAL`, mirroring how native terminal calls fail on
/// non-terminal fds.
const INVALID_SLOT : Int = 255

///|
fn stdio_slot_or_invalid(fd : @async/types.Fd) -> Int raise {
  stdio_slot(fd).unwrap_or(INVALID_SLOT)
}
