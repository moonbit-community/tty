///|
fn moon_home() -> String? {
  match @env.get_env_var("MOON_HOME") {
    Some(path) => Some(path)
    None => @env.get_env_var("HOME").map(home => home + "/.moon")
  }
}

///|
#cfg(platform="windows")
fn tcc_path(moon_home : String) -> String {
  moon_home + "/bin/internal/tcc.exe"
}

///|
#cfg(not(platform="windows"))
fn tcc_path(moon_home : String) -> String {
  moon_home + "/bin/internal/tcc"
}

///|
async fn read_until_nul(pty : @pty.Pty, timeout_ms? : Int = 3000) -> String {
  let reader = pty.reader()
  let buf = Buffer()
  @async.with_timeout(timeout_ms, () => {
    for ;; {
      let tmp = FixedArray::make(1024, b'\x00')
      guard reader.read(tmp) is n && n > 0 else { break }
      let tmp = tmp.unsafe_reinterpret_as_bytes()[:n]
      if tmp.find(b"\x00") is Some(end) {
        buf.write_bytes(tmp[:end])
        break
      } else {
        buf.write_bytes(tmp)
      }
    }
  })
  @utf8.decode(buf.to_bytes())
}

///|
fn parse_build_output(output : &@io.Data) -> String raise {
  let output_text = output.text()
  for line in output_text.split("\n") {
    let line = line.trim()
    if line.has_prefix("{") {
      let data : &@io.Data = line
      let build_output = data.json()
      guard build_output is { "artifacts_path": [String(artifacts_path)], .. } else {
        fail("invalid build output: \{output_text}")
      }
      return artifacts_path
    }
  }
  fail("missing build output JSON: \{output_text}")
}

///|
async fn build(name : String) -> String {
  let (build_exit, build_stdout, build_stderr) = @process.collect_output(
    "moon",
    ["-C", "tests/\{name}", "run", ".", "--build-only"],
  )
  guard build_exit is 0 else { fail("build failed: \{build_stderr.text()}") }
  parse_build_output(build_stdout)
}

///|
#cfg(not(platform="windows"))
async test "isatty" {
  @async.with_task_group() <| group => {
    let artifacts_path = build("isatty")
    guard moon_home() is Some(moon_home) else {
      fail("MOON_HOME and HOME are not set")
    }
    let pty = @pty.Pty::spawn(group, [tcc_path(moon_home), "@\{artifacts_path}"])
    defer pty.close()
    let output = read_until_nul(pty)
    assert_true(output.contains("isatty(stdin): true"))
    assert_true(output.contains("isatty(stdout): true"))
    assert_true(output.contains("isatty(stderr): true"))
    debug_inspect(pty.wait(), content="0")
  }
}

///|
#cfg(not(platform="windows"))
async test "Tty::open" {
  @async.with_task_group() <| group => {
    let artifacts_path = build("open")
    guard moon_home() is Some(moon_home) else {
      fail("MOON_HOME and HOME are not set")
    }
    let pty = @pty.Pty::spawn(
      group,
      [tcc_path(moon_home), "@\{artifacts_path}"],
      cols=100,
      rows=30,
    )
    defer pty.close()
    let output = read_until_nul(pty)
    assert_true(output.contains("open: ok"))
    assert_true(output.contains("rows: 30"))
    assert_true(output.contains("cols: 100"))
    assert_true(output.contains("open-write: ok"))
    debug_inspect(pty.wait(), content="0")
  }
}
