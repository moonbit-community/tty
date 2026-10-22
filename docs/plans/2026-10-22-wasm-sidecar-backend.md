# One terminal backend: the tty sidecar

Status: implemented.

## Goal

Make `moonbit-community/tty` work on the wasm target (programs run with
`moonrun`) without adding host imports to `moonrun`, and keep a single
implementation of the terminal layer instead of one per target.

## Problem

On wasm there is no C and `moonrun` exposes no terminal host imports;
`moonrun` must keep every host import forever, so adding terminal imports is
a heavy commitment. The native implementation (termios and `ioctl` stubs, a
`SIGWINCH` handler and self-pipe, a Windows console reader polling
`PeekConsoleInputW` every 10 ms, three `#cfg` variants of `Tty`) would have
had to be kept next to whatever wasm used.

## Shape

The terminal is owned by a small C sidecar process on every target. The
program talks to it over the sidecar's stdio pipes with a frame protocol
(`sidecar/README.md`); everything it needs is reachable through `@process`
and `@io`.

- `sidecar/sidecar.c`: the protocol part is shared, then one half per
  platform. Unix: single-threaded, `/dev/tty`, `cfmakeraw`, `TIOCGWINSZ`,
  `SIGWINCH` via handler plus `pselect`, which is correct in a
  single-threaded process; input is forwarded as VT bytes. Windows:
  `CONIN$`/`CONOUT$`, the former `state.c` console mode flags, a thread
  blocking in `ReadConsoleInputW`; input is forwarded as raw
  `INPUT_RECORD`s, window size events as resizes.
- It restores the terminal when the command pipe closes, so a parent killed
  with `kill -9` leaves the terminal usable.
- `internal/sidecar`: frame codec (`Connection`), process wrapper
  (`Sidecar`, implements `@io.Reader`/`@io.Writer`; a resize during a byte
  read is raised as `Resized`), and the locator.
- The executable comes from the same place on every target: the one named
  by the `TTY_SIDECAR` environment variable (an override, used by the tests
  and for development), else the one embedded for the running `<os>-<arch>`,
  written to a temporary directory, started and deleted again. The embedded
  table lives in `internal/sidecar/sidecars.generated.mbt`; the `sidecars`
  workflow rebuilds the five binaries whenever `sidecar/` changes on `main`,
  regenerates the file with `scripts/ci_sidecars.mbtx`, checks it compiles
  and commits it back to `main`. A self-spawning native variant (a
  constructor in a native stub) was tried and dropped: no magic in other
  people's programs.
- Root package: one `Tty` for all targets, with `sidecar :
  @sidecar.Sidecar?` and an input decoder that is either the VT byte decoder
  (`internal/input`) or the console record decoder (`internal/win32`, now
  free of FFI and fed by the sidecar). Only `Tty::open()` has terminal
  capabilities; `Tty::new` and `Tty::stdio` are stream handles whose
  `window_size`, `enter_raw_mode` and `leave_raw_mode` raise
  `OSError(ENOTSUP)`.
- Removed: `state.c`, `size.c`, `resize.c`, `tty_open.c`,
  `internal/win32/win32_input.c`, the `RawFdStream` impls, the
  `State` API and the per-platform `Tty` variants.

## Public API diff

Breaking, next release `0.6.0`:

- `State`, `State::make_raw`, `Tty::get_state`, `Tty::set_state` are gone.
  Raw mode is idempotent: `enter_raw_mode()` and `leave_raw_mode()` take no
  state and are `async`, because they talk to the sidecar. `with_raw_mode`
  is unchanged.
- `Tty::close` is `async` (it reaps the sidecar).
- `Tty::new` no longer raises (nothing is queried at construction).
- `pub impl Fd/Reader/Writer for @raw_fd.RawFdStream` are gone; the root no
  longer imports `raw_fd`, which was native only.
- `Tty::stdio()` has no raw mode, size or resize events; use `Tty::open()`.
- `isatty` raises `OSError(ENOTSUP)` on wasm.

## Invariants

- One code path for the terminal on every target; platform differences live
  in the two sidecar C files.
- The sidecar restores the terminal whenever its command pipe closes.
- `internal/sidecar` and `internal/win32` are internal and not downstream
  API.

## Validation

Run on macOS with moon 0.1.20261020 against the pinned `moonbitlang/async`:

- `moon fmt --check`, `git diff --check`: clean.
- `moon check --deny-warn` and `moon check --target wasm --deny-warn`: clean.
- `moon test --deny-warn`: root 30 passed; `moon test --target wasm
  --deny-warn` on root, `internal/sidecar`, `internal/win32`: 53 passed.
- `moon test` in `tests/`: 5 passed. Every runner, native or wasm, uses a
  sidecar compiled on the spot with `cc` (or `cl` on Windows) and named
  through `TTY_SIDECAR`; the wasm runners run under `moonrun`.
- The Windows sidecar and the console record path are validated by the
  windows-latest CI job through the same pty runners.

## Open questions

- A release must be cut after the `sidecars` workflow has committed the
  binaries for the current `sidecar/` sources; a package published from a
  commit whose table is stale or empty only works with `TTY_SIDECAR`.
  Writing an executable to a temporary directory is what EDR software flags
  and fails on `noexec` mounts; `TTY_SIDECAR` is the way out there.
- A sidecar-backed handle writes through the sidecar, so bytes written to
  the process's own stdout are not ordered against `Tty::write`.
