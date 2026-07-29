///|
/// End-to-end protocol tests against the real sidecar executable, compiled
/// from `sidecar/tty_sidecar.c` with the host C compiler. Unix-only: the
/// Windows sidecar needs a console and a cross-compiled binary.
#cfg(not(platform="windows"))
async fn sidecar_source() -> String {
  for prefix in [".", "..", "../.."] {
    let path = "\{prefix}/sidecar/tty_sidecar.c"
    if @async/fs.exists(path) {
      return path
    }
  }
  fail("sidecar/tty_sidecar.c not found from the test working directory")
}

///|
#cfg(not(platform="windows"))
async fn build_sidecar() -> String {
  let dir = @async/fs.tmpdir(prefix="tty-sidecar-test")
  let binary = "\{dir}/tty-sidecar"
  let code = @async/process.run("cc", [
    "-std=c99",
    "-O1",
    "-o",
    binary,
    sidecar_source(),
  ])
  guard code == 0 else { fail("cc failed to build the sidecar (exit \{code})") }
  binary
}

///|
/// Spawn the sidecar against a fresh listener with stdin redirected from a
/// pipe (so slot 0 is deterministically not a terminal), run `f` over the
/// handshaken control and event connections, then shut the sidecar down and
/// assert a clean exit.
#cfg(not(platform="windows"))
async fn with_sidecar(
  f : async (@async/socket.Tcp, @async/socket.Tcp) -> Unit,
) -> Unit {
  let binary = build_sidecar()
  let token = "cafebabe"
  @async.with_task_group() <| group => {
    let server = @async/socket.TcpServer(
      @async/socket.Addr::parse("127.0.0.1:0"),
    )
    defer server.close()
    let (stdin_read, stdin_write) = @async/pipe.pipe()
    defer {
      stdin_write.close()
      stdin_read.close()
    }
    let process = @async/process.spawn(
      group,
      binary,
      ["--port", server.addr.port().to_string()],
      extra_env={ "MOONBIT_TTY_SIDECAR_TOKEN": token },
      stdin=stdin_read,
    )
    let (control, _) = server.accept()
    defer control.close()
    @sidecar.read_handshake(
      control as &@async/io.Reader,
      magic=@sidecar.MAGIC_CONTROL,
      token=b"cafebabe",
    )
    let (events, _) = server.accept()
    defer events.close()
    @sidecar.read_handshake(
      events as &@async/io.Reader,
      magic=@sidecar.MAGIC_EVENT,
      token=b"cafebabe",
    )
    f(control, events)
    let response = request(control, Shutdown, id=99)
    debug_inspect(response, content="Acknowledged")
    debug_inspect(process.wait(), content="0")
  }
}

///|
#cfg(not(platform="windows"))
async fn request(
  control : @async/socket.Tcp,
  request : @sidecar.Request,
  id~ : UInt,
) -> @sidecar.Response {
  @async/io.Writer::write(control, request.encode(id~))
  @sidecar.Response::read(control as &@async/io.Reader, request, id~)
}

///|
#cfg(not(platform="windows"))
async test "sidecar answers terminal queries on pipe stdio" {
  with_sidecar((control, _events) => {
    // stdin is a pipe, so it is deterministically not a terminal.
    debug_inspect(
      request(control, IsATty(which=0), id=1),
      content="IsATty(false)",
    )
    // Raw mode needs a terminal; a pipe reports the tcgetattr errno (ENOTTY).
    guard request(control, EnterRawMode(input=0, output=1), id=2)
      is Error(errno=enter_errno) else {
      fail("expected raw mode on a pipe to fail")
    }
    assert_eq(enter_errno, 25)
    // Leaving raw mode without having entered it is a no-op.
    debug_inspect(
      request(control, LeaveRawMode(input=0, output=1), id=3),
      content="Acknowledged",
    )
    guard request(control, WinSize(which=0), id=4) is Error(..) else {
      fail("expected window size on a pipe to fail")
    }
    debug_inspect(
      request(control, Watch(enable=true), id=5),
      content="Acknowledged",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "sidecar rejects invalid terminal slots" {
  with_sidecar((control, _events) => {
    guard request(control, IsATty(which=9), id=1) is Error(errno~) else {
      fail("expected an invalid slot to be rejected")
    }
    // EINVAL on both Linux and macOS.
    assert_eq(errno, 22)
  })
}
