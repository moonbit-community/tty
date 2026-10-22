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
fn runner_args(name : String, target~ : String = "native") -> Array[String] {
  let args = [
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
  if target == "wasm" {
    // A wasm runner reaches the terminal through the sidecar process.
    ["env", "\{SIDECAR_ENV}=\{sidecar_path()}", ..args]
  } else {
    args
  }
}

///|
const SIDECAR_ENV : String = "TTY_SIDECAR"

///|
fn sidecar_path() -> String {
  let cwd = @env.current_dir().unwrap_or(".")
  "\{cwd}/\{tests_path("_build/sidecar")}"
}

///|
/// Compile `sidecar/sidecar.c` for the wasm runners.
async fn build_sidecar() -> Unit {
  let (exit, _, stderr) = @process.collect_output("cc", [
    "-O2",
    "-o",
    sidecar_path(),
    tests_path("../sidecar/sidecar.c"),
  ])
  guard exit is 0 else { fail("build sidecar failed: \{stderr.text()}") }
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
#cfg(not(platform="windows"))
async test "Tty::open on wasm through the sidecar" {
  @async.with_task_group() <| group => {
    build_sidecar()
    build_runner("open", target="wasm")
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
#cfg(not(platform="windows"))
async test "resize event on wasm through the sidecar" {
  @async.with_task_group() <| group => {
    build_sidecar()
    build_runner("resize", target="wasm")
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
