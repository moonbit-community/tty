# WebAssembly support through a tty sidecar

Status: implemented.

## Goal

Let `moonbit-community/tty` programs run as wasm under `moonrun` with a
working `Tty::open()`: raw mode, window size, resize events and input through
the controlling terminal. Native behaviour does not change.

## Problem

On the wasm target there is no C. The root package's termios, `ioctl`,
`/dev/tty` and `SIGWINCH` stubs have no equivalent, and `moonrun` exposes no
terminal host imports. `moonrun` must keep every host import forever, so
adding terminal imports there is a heavy commitment for a feature that only
some programs need.

## Shape

A 50 KB C program, `sidecar/sidecar.c`, owns the terminal and is driven over
its stdio pipes with a length-prefixed frame protocol (`sidecar/README.md`).
Everything the wasm program needs is reachable with `@process` and `@io`,
which `moonrun` already provides. Validated end to end in a standalone proof
of concept on native and on wasm under `moonrun 0.1.20261020`, including
terminal restoration after `kill -9` of the parent.

New package `internal/sidecar`:

- `Connection`: frame encoder/decoder over `&@io.Reader` / `&@io.Writer`,
  unit-tested with pipes on every target.
- `Sidecar`: spawns the executable (`@process.spawn_orphan`, the child stays
  in our session so `/dev/tty` is reachable), reads the hello frame, caches
  the size, exposes `set_raw`, `write`, `size`, `close`. It implements
  `@io.Reader`; a `RESIZE` frame read while a byte read is in progress is
  raised as `Resized` so the input decoder is interrupted, the same effect the
  native backend gets by cancelling the decoder from its resize watcher.
- `locate.mbt`: `TTY_SIDECAR` environment variable first, then an embedded
  executable for the running `<os>-<arch>` written to `@fs.tmpdir` and
  deleted once the process is running. `embedded.mbt` holds the (initially
  empty) table that `scripts/embed_sidecar.py` fills; shipping binaries is a
  release decision outside this plan.

Root package:

- `supported_targets` gains `wasm`. Native code is gated with
  `#cfg(target="native")` so files stay shared and imports stay anchored.
- On wasm `Tty` carries `sidecar : @sidecar.Sidecar?`. `Tty::open()` spawns
  the sidecar and wraps it as both `Reader` and `Writer`. `Tty::new` /
  `Tty::stdio` give stream handles without a sidecar: VT output, decoding and
  queries work, `window_size` and the state operations raise
  `OSError(ENOTSUP)`, as they already do for pipes on native.
- `State` on wasm is one byte (raw or not); `get_state` / `set_state` /
  `make_raw` map onto `set_raw`. The `.mbti` is unchanged.
- `isatty` raises `OSError(ENOTSUP)` on wasm; there is no descriptor kind
  query in `moonbitlang/async`'s public API.
- `internal/win32` gains `wasm` in `supported_targets`; its console reader
  file is native-only, the record parsers are shared.

Tests:

- `internal/sidecar` protocol tests with `@pipe` on native and wasm.
- `tests/`: the `Tty::open` and `resize event` pty tests also build the
  runners for wasm, compile the sidecar with `cc`, and run them under
  `moonrun` with `TTY_SIDECAR` set. Unix only. `tests/resize` switches from
  `Tty::stdio()` to `Tty::open()` so one runner serves both targets.
- CI adds `moon check --target wasm --deny-warn` and
  `moon test --target wasm --deny-warn` on Linux and macOS.

## Public API diff

The root package used `@async/raw_fd.RawFdStream` to wrap `/dev/tty` and the
Windows console devices, and implemented `Fd`, `Reader` and `Writer` for it.
`raw_fd` is native only, and the orphan rule keeps those impls in the root,
so the root could not support wasm while importing it. `Tty::open()` now
opens the terminal with `@async/fs.open` on both platforms (current
`moonbitlang/async` classifies non-regular handles with `GetFileType` and
skips the stat probing that made this fail in 0.19.4) and the three
`RawFdStream` impls are removed from the public API. This is a breaking
change for callers passing a `RawFdStream` to `Tty::new`; the next release
is `0.6.0`. `tty_open.c` is gone with it. Nothing else in the `.mbti`
changes besides the new `internal/sidecar` interface.

## Invariants

- Native code paths, C stubs and behaviour are untouched.
- Only `Tty::open()` has terminal capabilities on wasm.
- The sidecar restores the terminal whenever its command pipe closes.

## Validation

Run on macOS with moon 0.1.20261020 against the pinned `moonbitlang/async`:

- `moon fmt --check`, `git diff --check`: clean.
- `moon check --deny-warn` and `moon check --target wasm --deny-warn`: clean.
- `moon test --deny-warn`: all tty tests pass (the only failures are
  `moonbitlang/async`'s own DNS tests, which depend on the network).
- `moon test --target wasm --deny-warn` on the root and `internal/sidecar`
  packages: 33 passed.
- `moon test` in `tests/`: 5 passed, including the two new wasm runner tests
  that build the sidecar with `cc` and drive `moonrun` through a pty.
- `moon info`: `internal/sidecar/pkg.generated.mbti` is new; the root
  `.mbti` loses exactly the three `RawFdStream` impls.

## Public API audit

- Native `.mbti`: the three `pub impl ... for @raw_fd.RawFdStream` lines are
  removed, nothing else changes.
- wasm only, not visible in the generated interface: `Tty::set_state`,
  `Tty::enter_raw_mode`, `Tty::leave_raw_mode` are `async` and raise `Error`
  rather than `OSError`, because they write to the sidecar's pipe.
  `Tty::new` cannot fail on wasm but keeps the `raise` signature so
  `Tty::stdio` stays shared.
- `internal/sidecar` is internal and not downstream API.

## Open questions

- Distribution of per-platform sidecar binaries (CI build matrix, size,
  EDR and `noexec` temp directories). A Windows sidecar needs
  `ReadConsoleInput` and is not part of this plan.
