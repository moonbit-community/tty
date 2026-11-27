# Native `moonbitlang/core/async/tty` backend

Status: implemented.

## Goal

Replace the native controlling-terminal backend in root `moonbit-community/tty`
with `moonbitlang/core/async/tty`, while keeping `internal/sidecar` for the
`wasm` target and keeping the public API (`.mbti`) unchanged.

## Problem

On native targets, `Tty::open()` currently spawns the C sidecar process via
`internal/sidecar`, which embeds ~9.9 MB of sidecar binaries in
`internal/sidecar/sidecars.generated.mbt`, extracts an executable to a
temporary directory at runtime, and relays terminal I/O over pipes.

The MoonBit standard library now provides `moonbitlang/core/async/tty` for
native targets (Linux, macOS, Windows), sharing the same runtime event loop and
`SIGWINCH` handling as `moonbitlang/async@0.22.7` via
`moonbitlang/core/async/runtime_internal`.

## Shape

- `moon.pkg`:
  - Remove unconditional `"moonbit-community/tty/internal/sidecar"` import.
  - Add `#cfg(target="native")` imports for `"moonbitlang/core/async/tty" @core_tty`
    and `"moonbitlang/core/async/os_error" @core_os_error`.
  - Add `#cfg(target="wasm")` import for `"moonbit-community/tty/internal/sidecar"`.
  - Add target file mapping in `options(...)`:
    - `"terminal_native.mbt": [ "native" ]`
    - `"terminal_wasm.mbt": [ "wasm" ]`
  - Keep `"native-stub": [ "isatty.c" ]` since `moonbitlang/core/async/tty` has
    no `isatty`.
- `terminal_native.mbt`:
  - Private `Terminal` wrapping `@core_tty.Tty`, `@async/io.ReaderBuffer`, and
    `mut raw : Bool`.
  - `Terminal::open` calls `@core_tty.open()`.
  - `Terminal::size` calls `tty.size()` and maps `@core_os_error.OsError` to
    `@os_error.OSError` so `Tty::window_size` preserves its exact error type.
  - `Terminal::is_raw` / `Terminal::set_raw` delegate to
    `enter_raw_mode` / `leave_raw_mode` and track `raw` for nested `State(Bool)`
    composition.
  - `Terminal::close` leaves raw mode if currently raw (idempotent); underlying
    handle cleanup and exit restoration belong to `core/async/tty`'s event loop
    exit hook. `Terminal::wait` is a `nocancel` no-op.
  - `@async/io.Reader::_direct_read` calls `tty.wait_resize()`, raising private
    `Resized` on `Resize` and calling `tty.read_into(...)` on `Input`.
  - `@async/io.Writer::write_once` writes through `tty.write(...)`.
- `terminal_wasm.mbt`:
  - Private `Terminal(@sidecar.Sidecar)` forwarding all backend methods and
    translating `@sidecar.Resized` into private `Resized`.
- Root shared files (`tty.mbt`, `state.mbt`, `size.mbt`, `io.mbt`):
  - Replace direct `@sidecar.Sidecar` / `@sidecar.Resized` references with
    private `Terminal` and `Resized`.
- `tests/isatty_test.mbt`:
  - Native `Tty::open` and `resize event` PTY tests run directly without
    building or injecting a sidecar; wasm tests continue exercising the sidecar.
- Docs (`README.md`, `docs/architecture.md`, `docs/plan.md`):
  - Record that native uses `moonbitlang/core/async/tty` and wasm uses
    `internal/sidecar`.

## Public API Diff

- No breaking or non-breaking public API changes.
- All `.mbti` files remain unchanged.

## Invariants

- Native builds of root `moonbit-community/tty` do not import or embed
  `internal/sidecar`.
- Nested `enter_raw_mode` / `leave_raw_mode` scopes compose identically on
  native and wasm via `State(Bool)`.
- Resize notifications observed during request/response queries or mid-escape
  reads are preserved without losing input bytes.
- Stream handles from `Tty::new` and `Tty::stdio` still raise
  `OSError(ENOTSUP)` on `window_size`, `enter_raw_mode`, and `leave_raw_mode`.
- Wasm continues working through `internal/sidecar` (`TTY_SIDECAR` and embedded
  table).

## Acceptance Criteria

- Native `Tty::open`, `window_size`, raw mode, and `resize` events work via
  `moonbitlang/core/async/tty` with no sidecar binary.
- Wasm `Tty::open` and `resize` events continue passing via the sidecar.
- All workspace checks and tests pass with `--deny-warn` on native and wasm.
- `moon info` produces zero diff on `.mbti` files.

## Validation Plan

- `moon fmt --check`
- `moon check --deny-warn`
- `moon check --target wasm --deny-warn`
- `moon test --deny-warn`
- `moon test --target wasm --deny-warn`
- `moon test tests --deny-warn`
- `moon info` and verify `git diff -- '*.mbti'` is empty
- `git diff --check`

## Validation Results

Run on macOS (`moon 0.1.20261126`):

- `moon fmt --check`: clean.
- `moon check --deny-warn`: clean.
- `moon check --target wasm --deny-warn`: clean.
- `moon test --deny-warn`: 213 passed, 0 failed.
- `moon test --target wasm --deny-warn`: 208 passed, 0 failed.
- `moon test tests --deny-warn`: 5 passed, 0 failed (native `isatty`, native
  `Tty::open`, native `resize event`, plus wasm `Tty::open` and `resize event`
  against compiled sidecar).
- `TTY_TEST_SIDECAR=embedded moon test tests --deny-warn`: 5 passed, 0 failed.
- `moon info`: clean; `git diff -- '*.mbti'` is empty.
- `git diff --check`: clean.

## Public API Audit

- No public types, methods, traits, errors, or `.mbti` files changed.
- `Terminal` (`terminal_native.mbt`, `terminal_wasm.mbt`) and `Resized`
  (`tty.mbt`) are package-private; `Fd`/`Reader`/`Writer` impls on `Terminal`
  remain private.
- `Tty::window_size` continues raising `@os_error.OSError` by mapping
  `@core_os_error.OsError` to `@os_error.OSError` on native.
- Native builds of the root package no longer import `internal/sidecar`.
