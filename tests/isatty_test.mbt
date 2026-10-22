///|
fn tests_path(name : String) -> String {
  match @env.current_dir() {
    Some(cwd) if cwd.has_suffix("/tests") || cwd.has_suffix("\\tests") => name
    _ => "tests/\{name}"
  }
}

///|
fn target_dir(name : String) -> String {
  tests_path("_build/\{name}-run")
}

///|
/// Arguments for a runner, which reaches the terminal through the sidecar
/// built by `build_sidecar`, named to it through `TTY_SIDECAR`.
fn runner_args(name : String, target~ : String = "native") -> Array[String] {
  let moon = [
    "moon",
    "-C",
    tests_path(name),
    "run",
    ".",
    "--target",
    target,
    "--target-dir",
    target_dir(name),
  ]
  if is_windows() {
    ["cmd", "/c", "set TTY_SIDECAR=\{sidecar_path()}&& \{moon.join(" ")}"]
  } else {
    ["env", "TTY_SIDECAR=\{sidecar_path()}", ..moon]
  }
}

///|
fn is_windows() -> Bool {
  @async.platform is Windows
}

///|
fn sidecar_path() -> String {
  let cwd = @env.current_dir().unwrap_or(".")
  let name = if is_windows() { "sidecar.exe" } else { "sidecar" }
  "\{cwd}/\{tests_path("_build/\{name}")}"
}

///|
/// Compile the sidecar for this host with the system C compiler. Every pty
/// test does this into the same directory, which is why `moon.pkg` sets
/// `max_concurrent_tests = 1`: concurrent compilers trample each other's
/// object files.
async fn build_sidecar() -> Unit {
  @fs.mkdir(tests_path("_build"), allow_exist=true)
  // `cl` reports errors on stdout, so keep both streams for the message.
  let (exit, output) = if is_windows() {
    @process.collect_output_merged("cl", [
      "/nologo",
      "/O2",
      "/Fe:" + sidecar_path(),
      "/Fo:" + tests_path("_build") + "\\",
      tests_path("../sidecar/sidecar_win32.c"),
    ])
  } else {
    @process.collect_output_merged("cc", [
      "-O2",
      "-o",
      sidecar_path(),
      tests_path("../sidecar/sidecar.c"),
    ])
  }
  guard exit is 0 else { fail("build sidecar failed: \{output.text()}") }
}

///|
async fn read_until_text(
  pty : @pty.Pty,
  text : String,
  timeout_ms~ : Int32 = 10000,
) -> String {
  let reader = pty.reader()
  let needle = @utf8.encode(text)
  let buf = Buffer()
  @async.with_timeout(timeout_ms, () => {
    for ;; {
      let tmp = FixedArray::make(1024, b'\x00')
      guard reader.read(tmp) is n && n > 0 else { break }
      buf.write_bytes(tmp.unsafe_reinterpret_as_bytes()[:n])
      if buf.to_bytes().find(needle) is Some(_) {
        break
      }
    }
  })
  @utf8.decode(buf.to_bytes())
}

///|
async fn build_runner(name : String, target~ : String = "native") -> Unit {
  let (exit, _, stderr) = @process.collect_output("moon", [
    "-C",
    tests_path(name),
    "run",
    ".",
    "--build-only",
    "--target",
    target,
    "--target-dir",
    target_dir(name),
  ])
  guard exit is 0 else { fail("build \{name} runner failed: \{stderr.text()}") }
}

///|
async test "isatty" {
  @async.with_task_group() <| group => {
    build_runner("isatty")
    let pty = @pty.spawn(group, runner_args("isatty"), no_wait=true)
    defer pty.close()
    let output = read_until_text(pty, "isatty(stderr): true")
    assert_true(output.contains("isatty(stdin): true"))
    assert_true(output.contains("isatty(stdout): true"))
    assert_true(output.contains("isatty(stderr): true"))
    debug_inspect(pty.wait(), content="0")
  }
}

///|
async test "Tty::open" {
  @async.with_task_group() <| group => {
    build_sidecar()
    build_runner("open")
    let pty = @pty.spawn(
      group,
      runner_args("open"),
      cols=100,
      rows=30,
      no_wait=true,
    )
    defer pty.close()
    let output = read_until_text(pty, "open-write: ok")
    assert_true(output.contains("open: ok"))
    assert_true(output.contains("rows: 30"))
    assert_true(output.contains("cols: 100"))
    assert_true(output.contains("open-write: ok"))
    debug_inspect(pty.wait(), content="0")
  }
}

///|
async test "resize event" {
  @async.with_task_group() <| group => {
    build_sidecar()
    build_runner("resize")
    let pty = @pty.spawn(
      group,
      runner_args("resize"),
      cols=100,
      rows=30,
      no_wait=true,
    )
    defer pty.close()
    assert_true(read_until_text(pty, "ready").contains("ready"))
    pty.write(b"x")
    assert_true(read_until_text(pty, "armed").contains("armed"))
    pty.resize(cols=101, rows=31)
    let output = read_until_text(pty, "resize:")
    assert_true(output.contains("resize: rows=31 cols=101"))
    debug_inspect(pty.wait(), content="0")
  }
}

///|
async test "Tty::open on wasm through the sidecar" {
  @async.with_task_group() <| group => {
    build_runner("open", target="wasm")
    build_sidecar()
    let pty = @pty.spawn(
      group,
      runner_args("open", target="wasm"),
      cols=100,
      rows=30,
      no_wait=true,
    )
    defer pty.close()
    let output = read_until_text(pty, "open-write: ok", timeout_ms=30000)
    assert_true(output.contains("open: ok"))
    assert_true(output.contains("rows: 30"))
    assert_true(output.contains("cols: 100"))
    assert_true(output.contains("open-write: ok"))
    debug_inspect(pty.wait(), content="0")
  }
}

///|
async test "resize event on wasm through the sidecar" {
  @async.with_task_group() <| group => {
    build_runner("resize", target="wasm")
    build_sidecar()
    let pty = @pty.spawn(
      group,
      runner_args("resize", target="wasm"),
      cols=100,
      rows=30,
      no_wait=true,
    )
    defer pty.close()
    assert_true(
      read_until_text(pty, "ready", timeout_ms=30000).contains("ready"),
    )
    pty.write(b"x")
    assert_true(read_until_text(pty, "armed").contains("armed"))
    pty.resize(cols=101, rows=31)
    let output = read_until_text(pty, "resize:")
    assert_true(output.contains("resize: rows=31 cols=101"))
    debug_inspect(pty.wait(), content="0")
  }
}
