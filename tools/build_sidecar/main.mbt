///|
/// Cross-compiles `sidecar/tty_sidecar.c` for every supported wasm host with
/// `zig cc` and regenerates `internal/sidecar/client/binaries.mbt` (the
/// embedded binaries in the sidecar client package).
///
/// Run from anywhere inside the repository:
///
///   cd tools && moon run build_sidecar
///
/// zig is found via `--zig` or `PATH`; otherwise a pinned release is
/// downloaded (with `curl` + `tar`) into `~/.cache/moonbit-tty/zig`.
struct SidecarTarget {
  // Constructor name of `HostPlatform` in the generated match.
  platform : String
  arch : String
  zig_target : String
  extra_flags : Array[String]
  artifact : String
}

///|
let sidecar_targets : Array[SidecarTarget] = [
  {
    platform: "Linux",
    arch: "x86_64",
    zig_target: "x86_64-linux-musl",
    extra_flags: ["-static", "-s"],
    artifact: "tty-sidecar-linux-x86_64",
  },
  {
    platform: "MacOS",
    arch: "aarch64",
    zig_target: "aarch64-macos-none",
    extra_flags: [],
    artifact: "tty-sidecar-macos-aarch64",
  },
  {
    platform: "Windows",
    arch: "x86_64",
    zig_target: "x86_64-windows-gnu",
    extra_flags: ["-s", "-lws2_32"],
    artifact: "tty-sidecar-windows-x86_64.exe",
  },
]

///|
const PINNED_ZIG_VERSION : String = "0.16.0"

///|
async fn main {
  let cmd = @argparse.Command("build_sidecar", options=[
    @argparse.OptionArg("zig", long="zig"),
    @argparse.OptionArg("zig-version", long="zig-version"),
  ])
  let matches = cmd.parse()
  let zig_version = matches.values
    .get("zig-version")
    .map(values => values[0])
    .unwrap_or(PINNED_ZIG_VERSION)
  let root = repo_root()
  let zig = if matches.values.get("zig").map(values => values[0]) is Some(zig) {
    zig
  } else {
    find_or_install_zig(zig_version)
  }
  println("using zig: \{zig}")
  let source = "\{root}/sidecar/tty_sidecar.c"
  let build_dir = @async/fs.tmpdir(prefix="tty-sidecar-build")
  let binaries : Array[(SidecarTarget, Bytes)] = []
  for target in sidecar_targets {
    let out = "\{build_dir}/\{target.artifact}"
    let args = ["cc", "-target", target.zig_target, "-Os"] +
      target.extra_flags +
      ["-o", out, source]
    let code = @async/process.run(zig, args)
    guard code == 0 else {
      fail("zig cc failed for \{target.zig_target} (exit \{code})")
    }
    let binary = @async/fs.read_file(out).binary()
    println(
      "built \{target.artifact}: \{binary.length()} bytes (\{target.zig_target})",
    )
    binaries.push((target, binary))
  }
  let out_path = "\{root}/internal/sidecar/client/binaries.mbt"
  @async/fs.write_file(out_path, render_binaries(binaries))
  println("wrote \{out_path}")
}

///|
/// Locate the repository root by walking up from the working directory.
async fn repo_root() -> String {
  for prefix in [".", "..", "../..", "../../.."] {
    if @async/fs.exists("\{prefix}/sidecar/tty_sidecar.c") {
      return prefix
    }
  }
  fail("run this tool from inside the tty repository")
}

///|
async fn zig_works(zig : String) -> Bool {
  try {
    let (code, _) = @async/process.collect_stdout(zig, ["version"])
    code == 0
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}

///|
async fn find_or_install_zig(version : String) -> String {
  if zig_works("zig") {
    return "zig"
  }
  guard @env.get_env_var("HOME") is Some(home) else {
    fail("zig not found on PATH and $HOME is unset; pass --zig")
  }
  let cache = "\{home}/.cache/moonbit-tty/zig"
  let dist = "zig-\{zig_host_target()}-\{version}"
  let installed = "\{cache}/\{dist}/zig"
  if @async/fs.exists(installed) && zig_works(installed) {
    return installed
  }
  println("zig not found; downloading \{dist} ...")
  @async/fs.mkdir(cache, recursive=true)
  let archive = "\{cache}/\{dist}.tar.xz"
  let url = "https://ziglang.org/download/\{version}/\{dist}.tar.xz"
  let code = @async/process.run("curl", ["-fSL", "-o", archive, url])
  guard code == 0 else { fail("failed to download \{url} (exit \{code})") }
  let code = @async/process.run("tar", ["-xf", archive, "-C", cache])
  guard code == 0 else { fail("failed to extract \{archive} (exit \{code})") }
  guard zig_works(installed) else {
    fail("downloaded zig at \{installed} does not run")
  }
  installed
}

///|
async fn zig_host_target() -> String {
  let (code, out) = @async/process.collect_stdout("uname", ["-sm"])
  guard code == 0 else { fail("uname -sm exited with \{code}") }
  let parts = @utf8.decode(out.binary())
    .trim()
    .split(" ")
    .map(part => part.to_owned())
    .collect()
  guard parts is [os, arch] else { fail("unexpected uname output") }
  let os = match os {
    "Darwin" => "macos"
    "Linux" => "linux"
    other => fail("unsupported build host OS: \{other}")
  }
  let arch = match arch {
    "arm64" | "aarch64" => "aarch64"
    "x86_64" | "amd64" => "x86_64"
    other => fail("unsupported build host arch: \{other}")
  }
  "\{arch}-\{os}"
}

///|
const CHUNK_SIZE : Int = 4096

///|
fn render_binaries(binaries : Array[(SidecarTarget, Bytes)]) -> String {
  let out = StringBuilder::new()
  out.write_string(
    (
      #|///|
      #|/// Embedded sidecar executables, keyed by host platform and architecture.
      #|/// REGENERATED by `tools/build_sidecar` (`cd tools && moon run
      #|/// build_sidecar`); do not edit by hand.
      #|fn sidecar_binary(platform : HostPlatform, arch : String) -> Bytes? {
      #|  match platform {
    ),
  )
  out.write_char('\n')
  for entry in binaries {
    let (target, _) = entry
    out.write_string(
      "    \{target.platform} => if arch == \"\{target.arch}\" { Some(\{binary_fn_name(target)}()) } else { None }\n",
    )
  }
  out.write_string(
    (
      #|  }
      #|}
      #|
      #|///|
      #|fn concat_chunks(chunks : Array[Bytes]) -> Bytes {
      #|  let buf = Buffer()
      #|  for chunk in chunks {
      #|    buf.write_bytes(chunk)
      #|  }
      #|  buf.contents()
      #|}
    ),
  )
  out.write_char('\n')
  for entry in binaries {
    let (target, binary) = entry
    out.write_string("\n///|\nfn \{binary_fn_name(target)}() -> Bytes {\n")
    out.write_string("  concat_chunks([\n")
    let mut offset = 0
    while offset < binary.length() {
      let end = @cmp.minimum(offset + CHUNK_SIZE, binary.length())
      out.write_string("    b\"")
      for i in offset..<end {
        out.write_string(escape_byte(binary[i]))
      }
      out.write_string("\",\n")
      offset = end
    }
    out.write_string("  ])\n}\n")
  }
  out.to_string()
}

///|
fn binary_fn_name(target : SidecarTarget) -> String {
  "sidecar_\{target.platform.to_lower()}_\{target.arch}"
}

///|
fn escape_byte(byte : Byte) -> String {
  let hex = (byte.to_int() + 0x100).to_string(radix=16)
  "\\x\{hex[1:]}"
}
