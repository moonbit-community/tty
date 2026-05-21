# Resize Events

## Goal

Add root `Tty` resize events on Unix using a process-global `SIGWINCH`
self-pipe, without turning `tonyfettes/tty/input` into an OS event source.

## Design

- Add root `Event` with `Input(@input.InputEvent)` and `Resize(WindowSize)`.
- Replace root `Tty::read_input` with `Tty::read_event(esc_timeout_ms?)`.
- Keep `@input.EventReader` as the byte-stream decoder. It still returns low
  level input/terminal-response events such as CPR.
- `Tty::query_cursor_position` continues to read the shared low-level
  `EventReader` directly and stores interleaved input in `pending_input` for a
  later `Tty::read_event`.
- Unix `Tty::read_event` races decoded input against a private process-global
  `SIGWINCH` watcher.
- The watcher is a singleton. It installs `sigaction(SIGWINCH, ...)` once and
  uses an async pipe created by `@async/pipe.pipe()`.
- The signal handler only writes one byte to the nonblocking pipe. `EAGAIN`
  means resize notifications are coalesced.
- On pipe notification, normal async code drains the pipe and calls
  `Tty::window_size()` on the current output fd. If the output is not a tty, the
  notification is ignored and the read keeps waiting.
- Windows resize events are left for a later Windows console-input backend.

## Public API Changes

- Add root `Event`.
- Add root `Tty::read_event`.
- Remove root `Tty::read_input`.
- Add `Eq` to `WindowSize` so root `Event` can derive `Eq`.
- Root `.mbti` should not expose the private resize watcher, self-pipe helper,
  or C stub functions.

## Acceptance

- Input-only loops can migrate from `Tty::read_input` to matching
  `Tty::read_event`.
- CPR interleaving still preserves input that arrives before the CPR response.
- Unix resize notifications are process-global and coalesced.
- Non-tty custom handles do not fail just because the process receives
  `SIGWINCH`.

## Validation

- `moon fmt`
- `moon test .`
- `moon test input`
- targeted example checks for `examples/input`, `examples/pager`,
  `examples/agent`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff

## Result

- Added root `Event::{ Input, Resize }`.
- Replaced root `Tty::read_input` with `Tty::read_event`.
- Added a Unix-only private `SigwinchWatcher` singleton backed by an async
  self-pipe.
- Added `resize.c` with a `SIGWINCH` handler that only writes to the pipe and
  chains to any previous handler.
- Updated examples to match `@tty.Input(...)` and ignore or redraw on
  `@tty.Resize(_)`.
- Left Windows resize event delivery for a later console-input backend.

## Public API Audit

- `pkg.generated.mbti` exposes the intended new root `Event`.
- `Tty::read_event(Self, esc_timeout_ms? : Int) -> Event` replaces
  `Tty::read_input`.
- `WindowSize` now derives `Eq` because root `Event` derives `Eq`.
- The resize watcher, self-pipe state, FFI install/drain helpers, and signal
  handler details remain private and do not appear in `.mbti`.

## Validation Results

- `moon fmt`: passed.
- `moon test .`: passed, 11 tests.
- `moon test input`: passed, 39 tests.
- `moon check examples/input`: passed.
- `moon check examples/pager`: passed.
- `moon check examples/agent`: passed.
- `moon test`: passed, 89 tests.
- `moon check`: passed.
- `moon info`: passed.
- `git diff --check`: passed.
