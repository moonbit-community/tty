# 2026-07-29 Wasm backend via native syscall sidecar

## Goal

Make `moonbit-community/tty` build and work on the `wasm` target (wasm1,
running under `moonrun`), which has no libc/syscall surface for `isatty`,
`termios`, `ioctl(TIOCGWINSZ)`, or `SIGWINCH`.

Approach requested by the user:

1. A small C sidecar program exposes the required terminal syscalls.
2. The sidecar is cross-compiled ahead of time for linux/amd64, macos/arm64,
   and windows/amd64 with `zig cc`.
3. At runtime the wasm program probes the host platform, writes the matching
   sidecar binary to a temporary location, spawns it, and proxies terminal
   calls to it over an efficient binary protocol.
4. The sidecar shuts down when the program exits and temporary files are
   cleaned up (best effort; see Limitations).
5. Build tooling is written in MoonBit.

## Why a sidecar works

- `moonrun` implements the `"moonbitlang/async"` wasm host module, so
  `moonbitlang/async` ≥ 0.20.2 provides process spawning, TCP sockets, file
  system, and stdio on wasm. Verified locally: a wasm program can spawn
  `uname -m` and read stdio handles.
- On wasm, `@async/types.Fd` is an opaque host handle (`UInt64`), so sidecar
  requests cannot name parent file descriptors directly. Instead the sidecar
  is spawned with **stdin/stdout/stderr inherited** — its fds 0/1/2 are the
  same open file descriptions as the wasm program's stdio — and requests name
  terminals by well-known slot (`0`, `1`, `2`). Terminal state (termios,
  window size) is a property of the terminal, not the fd, so operating on the
  sidecar's inherited fds is exact.
- The protocol runs on loopback TCP (`@async/socket` works on wasm on all
  three OSes), because the sidecar's stdio must stay attached to the
  terminal. The parent listens on an ephemeral 127.0.0.1 port; the sidecar
  connects back and authenticates with a token passed via environment
  variable.

## Architecture

```
wasm program (moonrun)                     native sidecar (inherits stdio)
┌───────────────────────┐                  ┌──────────────────────────────┐
│ @tty wasm files       │  control conn    │ fd0/1/2 = same terminal as   │
│  async isatty/state/  │◄────TCP─────────►│ parent; termios/ioctl/       │
│  size APIs            │  req/resp        │ GetConsoleMode/…             │
│                       │  event conn      │ SIGWINCH → resize events     │
│ resize watcher        │◄────TCP──────────│ (windows: size polling)      │
└───────────────────────┘  events only     └──────────────────────────────┘
```

Two connections keep concurrency trivial: the control connection is strict
request/response serialized under a lock; the event connection only carries
unsolicited events (resize), so any number of waiters can take turns reading
it without a frame dispatcher.

## Wire protocol (v1)

All integers little-endian. See `sidecar/PROTOCOL.md` for the authoritative
spec.

- Handshake (sidecar → parent, once per connection):
  `magic u32` (`"MTTC"` control / `"MTTE"` event), `proto u16` (=1),
  `token_len u16`, `token bytes`. The control handshake completes before the
  event connection opens, so the parent identifies connections by accept
  order. No info block: the parent already knows the platform (it picked the
  binary), and terminal state stays sidecar-side.
- Request (parent → sidecar, control conn):
  `op u8, req_id u32, len u16, payload[len]`.
- Response (sidecar → parent, control conn):
  `kind u8` (0 ok, 1 err), `req_id u32, len u16, payload[len]`.
  Error payload: `errno i32` (Unix `errno`; Windows `GetLastError`).
- Event (sidecar → parent, event conn):
  `kind u8` (=2), `req_id u32` (=0), `len u16`, payload
  `event u8` (1 = resize), `rows i32, cols i32`.

Ops: `0x01 ISATTY{which u8}` → `{tty u8}`; `0x02 ENTER_RAW{in u8, out u8}`;
`0x03 LEAVE_RAW{in u8, out u8}`; `0x05 WINSIZE{which u8}` →
`{rows i32, cols i32}`; `0x06 WATCH_RESIZE{enable u8}`; `0x07 SHUTDOWN`.

`which`/`in`/`out` ∈ {0,1,2} are sidecar stdio slots. Terminal state
(termios / console modes) never crosses the wire: `ENTER_RAW` captures and
raw-ifies inside the sidecar, `LEAVE_RAW` restores.

Safety net: if the sidecar loses the control connection while raw mode is
active, it restores the captured original state before exiting, so a crashed
program does not strand the terminal in raw mode.

## Runtime lifecycle (wasm)

1. First terminal call hits the lazy singleton client.
2. Platform: free-ride on the moonrun host primitive
   `"moonbitlang/async" "runtime/get_platform"` (same ABI as
   `@event_loop.platform`: 0/1/2). Arch: `uname -m` on unix (per the user's
   plan); windows assumes x86_64 (arm64 Windows runs x64 binaries).
3. Write the embedded sidecar binary for (platform, arch) into
   `@async/fs.tmpdir(prefix="moonbit-tty-sidecar.")`, chmod 755.
4. `TcpServer` on 127.0.0.1:0; random 16-byte token via host `random/fill`.
5. `spawn_orphan(binary, ["--port", port], extra_env={TOKEN})` — stdio
   inherited by default; orphan so no task group owns the sidecar.
6. Accept twice in order (control, then event), validate magic+token.
7. Unix: unlink the temp binary immediately after successful handshake.
8. No explicit shutdown hook exists on wasm; when the program exits, moonrun
   closes the sockets, the sidecar sees EOF, restores state if needed, and
   exits. `SHUTDOWN` op exists for tests and explicit teardown.

## Public API on wasm

Same package (`moonbit-community/tty`), same names, but syscall-backed
operations become `async` (they are socket round-trips):

- `pub async fn[T : Fd] isatty(fd : T) -> Bool raise` — exact for
  stdin/stdout/stderr (compared against `@async/stdio` handles); other
  handles return `false` (host handles cannot be translated).
- `Tty::enter_raw_mode / leave_raw_mode / window_size` become `async`;
  `State` does not exist on wasm (state lives in the sidecar), so
  `enter_raw_mode` returns `Unit` and `leave_raw_mode` takes no state.
  `get_state` / `set_state` / `State::make_raw` are native-only.
- `Tty::with_raw_mode`, `Tty::read_event`, queries: unchanged signatures
  (already async).
- Not available on wasm: `@tty/open.open()` (native-only sub-package; a
  sidecar-proxied wasm variant is future work).

`pkg.generated.mbti` stays native-only (gated in `targets`), matching
upstream async practice.

## Package/file layout

- `sidecar/tty_sidecar.c` — single-file C program (POSIX + Win32),
  `sidecar/PROTOCOL.md`.
- `internal/sidecar` — pure protocol encode/decode + handshake parsing,
  `native+wasm`, unit-tested on native.
- `open/` — new native-only sub-package (see restructure section above).
- Root package `supported_targets = "native+wasm"` with a `targets` map:
  - native-only: `isatty.mbt`, `state.mbt`, `size.mbt`, `win32_input.mbt`,
    `resize_unix.mbt`, `resize_win32.mbt`, `non_windows_imports.mbt`,
    `pkg.generated.mbti`, tests/wbtests.
  - shared: `fd.mbt` (trait `Fd` + impls), `state_types.mbt` (`State`),
    `size_types.mbt` (`WindowSize`), `io.mbt`, `tty.mbt`, `command.mbt`,
    `style.mbt`, `decstbm.mbt`.
  - wasm-only: `internal/sidecar/client` (sidecar client + lifecycle +
    generated `binaries.mbt`), root `tty_wasm.mbt`, `isatty_wasm.mbt`,
    `state_wasm.mbt`, `size_wasm.mbt`, `sidecar_imports.mbt` (import
    anchors).
- `internal/win32` becomes `native+wasm`; the `event_reader*.mbt` files and
  C stub stay native-only, pure record parsing stays shared (root's wasm
  anchor references it).
- `tools/` — separate MoonBit module (native) that cross-compiles the
  sidecar with `zig cc` (found via `MOONBIT_TTY_ZIG`/`PATH`, else downloaded
  and cached) and regenerates `internal/sidecar/client/binaries.mbt`.

## Root package restructure (breaking, decided 2026-07-29)

Root imports `moonbitlang/async/raw_fd`, which declares
`supported_targets = "-all+native"`, and moon has no per-target imports —
this alone blocks `moon check --target wasm`. Changing async upstream is not
an option (if upstream were changeable, the whole sidecar would be
unnecessary — the syscalls would go into moonrun instead). Decision: move
everything raw_fd-flavored out of the root package into a new native-only
sub-package, using a newtype to satisfy the orphan rule:

- `moonbit-community/tty/open` (native-only) owns `tty_open.c`, a public
  `Terminal(@async/raw_fd.RawFdStream)` wrapper implementing the root
  `Reader`/`Writer`/`Fd` traits (trait foreign + type local = allowed), and
  `pub async fn open() -> @tty.Tty` replacing `Tty::open` for both Unix and
  Windows.
- Root package drops the `raw_fd` import, the three `RawFdStream` trait
  impls, and `Tty::open`.

Breaking changes for the next minor release:

- `Tty::open()` → `@tty/open.open()`.
- `RawFdStream` can no longer be passed directly to `Tty::new`/`isatty`;
  wrap it in `@tty/open.Terminal` instead.

A wasm `open()` (sidecar-proxied `/dev/tty` I/O) is out of scope for this
task; the protocol reserves room for `OPEN_TTY`/`READ`/`WRITE`/`CLOSE`
opcodes.

## Design choices

- Binary protocol (7-byte headers) instead of JSON-RPC to keep per-call
  overhead minimal, per the user's requirement.
- Two TCP connections instead of one multiplexed stream: removes the need
  for a background dispatcher task under structured concurrency.
- `spawn_orphan` instead of group-owned spawn: the sidecar is a global
  resource, not owned by any user task group; lifetime is bounded by the
  sockets.
- Fresh tmpdir per run instead of a shared cache: no cache invalidation, and
  matches the user's "write, then remove" plan.
- Embedded binaries as chunked `Bytes` literals in a generated wasm-only
  file: mooncakes publishes source, so blobs must live in source form.

## Limitations (documented in README)

- `Tty::open` is unavailable on wasm.
- `isatty` is exact only for stdio handles on wasm.
- Windows resize events are polled by the sidecar (~250 ms), not event-driven.
- On Windows the temp sidecar binary cannot be unlinked while running and may
  outlive the process in the temp dir.
- Wasm artifact grows by the embedded sidecar binaries (~all platforms).

## Validation

- `moon fmt`, `moon info` (audit `.mbti`: native surface must be unchanged),
  `moon check`, `moon check --target native`, `moon test` (native).
- `tests/`: native protocol test — compiles the sidecar with `cc`, spawns it
  with `--port`, asserts handshake, `ISATTY` on pipes = false, `GET_STATE`
  on pipes = errno error, `MAKE_RAW` round-trip, `SHUTDOWN` → clean exit.
- Wasm: `moon check --target wasm` with patched async; smoke test under a
  real pty (`script -q`) running a wasm demo via moonrun: `isatty` true,
  `window_size` sane, raw-mode enter/leave round-trip.

## Windows input fidelity (decided 2026-07-29)

Full fidelity via the sidecar, not a VT-input fallback: with `WATCH`
enabled the sidecar becomes the console's sole `INPUT_RECORD` consumer (a
dedicated blocking reader thread) and streams raw records over the event
connection. `internal/win32` was split so its pure record routing
(`RecordRouter`) is shared by the native `EventReader` (C polling source)
and the wasm `StreamEventReader` (sidecar stream source). On wasm, `Tty`
picks its input backend at runtime: ANSI decoding everywhere, records on a
Windows console. Resize on Windows arrives as `WINDOW_BUFFER_SIZE_EVENT`
records — no polling. On Unix the event connection carries only coalesced
resize events (non-blocking sidecar-side, latest size wins), so watching is
always safe to enable.

## Validation results (2026-07-29)

- `moon fmt` / `moon info` clean; `.mbti` diffs limited to the intended
  breaking changes (root: `Tty::open` + RawFdStream impls removed;
  `InputRecord::parse` takes `BytesView`; new `open` package surface).
- `moon check` and `moon check --target wasm`: 0 warnings, 0 errors.
- `moon test --target native`: 203 tests pass, including
  `internal/sidecar/livetest` (compiles the real sidecar with `cc`, spawns
  it, validates handshake, isatty-on-pipes, `ENOTTY` on raw mode over
  pipes, `EINVAL` on invalid slots, clean `SHUTDOWN` exit) and the
  `EventStream` cancellation-safety test over a real pipe.
- `moon test --target wasm`: 124 tests pass under moonrun, including shared
  `Tty` pipe tests that spawn the embedded sidecar for real.
- `tools/build_sidecar` cross-compiles the three sidecars with zig cc
  (25.6 KB linux static, 52.2 KB macos, 60.4 KB windows) and regenerates
  `internal/sidecar/client/binaries.mbt` (~554 KB source).
- Pty smoke test (`tests/probe` + a python pty driver), all checks green on
  BOTH targets: isatty=true on a pty, window size 30x100, raw mode entered,
  SIGWINCH resize delivered as `resize: 40x120` (wasm: through the sidecar
  event connection), input decoding in raw mode, clean exit. Sidecar
  processes exit on socket EOF (none left behind) and the Unix temp binary
  is unlinked after handshake.
- Upstream bug found on the way: `@async/fs.write_file` fails with `ENOENT`
  under moonrun (wasm) even when the parent directory exists — its open
  flags are mistranslated by the host. Worked around with
  `@async/fs.create` + `File::write`; worth reporting to
  moonbitlang/async / moonrun.

## Status

- [x] async bumped to 0.20.2
- [x] sidecar C + protocol doc
- [x] internal/sidecar package (Request/Response/EventStream)
- [x] root package wasm wiring (+ windows record streaming)
- [x] build tool + generated blobs
- [x] native protocol tests (livetest)
- [x] wasm check + wasm test suite
- [x] pty smoke test on native and wasm
- [x] docs (architecture, README, CI)
