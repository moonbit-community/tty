///|
/// Environment variable naming an external sidecar executable to use.
pub const SIDECAR_ENV : String = "TTY_SIDECAR"

///|
/// `<os>-<arch>` of the running host, the key into `embedded_sidecars`.
async fn platform_key() -> String {
  let os = match @async.platform {
    Linux => "linux"
    MacOS => "macos"
    Windows => "windows"
  }
  let arch = match @async.platform {
    Windows =>
      match @env.get_env_var("PROCESSOR_ARCHITECTURE") {
        Some("ARM64") => "arm64"
        _ => "x86_64"
      }
    _ => {
      let (exit, out) = @async/process.collect_stdout("uname", ["-m"])
      guard exit == 0 else { return os + "-unknown" }
      match out.text().trim().to_owned() {
        "aarch64" | "arm64" => "arm64"
        "x86_64" | "amd64" => "x86_64"
        other => other
      }
    }
  }
  "\{os}-\{arch}"
}

///|
/// Start a sidecar: the executable named by `TTY_SIDECAR`, else the embedded
/// one for this host written to a temporary directory.
pub async fn open() -> Sidecar {
  if @env.get_env_var(SIDECAR_ENV) is Some(path) && path != "" {
    return spawn(path)
  }
  if embedded_sidecars.length() == 0 {
    raise @os_error.OSError(
      @os_error.errno_ENOTSUP,
      context="@tty.Tty::open(): no tty sidecar executable, set \{SIDECAR_ENV}",
    )
  }
  let key = platform_key()
  guard embedded_sidecars.get(key) is Some(executable) else {
    raise @os_error.OSError(
      @os_error.errno_ENOTSUP,
      context="@tty.Tty::open(): no embedded tty sidecar for \{key}, set \{SIDECAR_ENV}",
    )
  }
  let dir = @async/fs.tmpdir(prefix="tty-sidecar")
  errdefer @async/fs.rmdir(dir, recursive=true)
  // Windows runs executables by suffix, forbids `chmod`, and keeps a
  // running image locked, which is why the directory outlives `spawn` and
  // is removed by `Sidecar::wait`.
  let path = if @async.platform is Windows {
    "\{dir}/sidecar.exe"
  } else {
    "\{dir}/sidecar"
  }
  @async/fs.write_file(path, executable, permission=0o755)
  if !(@async.platform is Windows) {
    @async/fs.chmod(path, 0o755)
  }
  spawn(path, temp_dir=Some(dir))
}
