# Terminal Window Size Query

## Goal

Expose a low-level way to query the current terminal window size from an
`Output` handle so demos can decide how much of the terminal to repaint without
introducing a renderer, scrollback model, or resize-event loop.

## Status

Done.

## Context And Decisions

- Window size is an output-side terminal capability: callers need to know how
  many rows and columns are available for painting.
- This task only adds synchronous querying. Resize notification and event
  delivery need a separate plan because Unix `SIGWINCH` and Windows console
  input events have different ownership and lifetime implications.
- The API is attached to `Output`, not `Input`, because Windows size queries
  naturally use the output console screen buffer handle.
- A non-tty output should fail with the platform `OSError`, matching existing
  state operations on non-tty input.

## Target Files

- `size.mbt`
- `size.c`
- `moon.pkg`
- `tty_wbtest.mbt`
- `tty_test.mbt`
- `docs/architecture.md`
- `docs/plan.md`
- `pkg.generated.mbti`

## Public API Changes

Add:

```mbt
pub struct WindowSize {
  rows : Int
  cols : Int
}

pub fn Output::window_size(self : Output) -> WindowSize raise @os_error.OSError
```

Consumer story:

- Demos and applications can query the visible terminal dimensions before
  choosing a repaint strategy.
- Callers can read `rows` and `cols` directly.
- Construction is kept package-private because external callers should get a
  value from the terminal, not forge one for terminal state.

This is additive and not breaking.

## Invariants

- `WindowSize.rows > 0` and `WindowSize.cols > 0` when the query succeeds.
- Platform-specific querying stays inside the root package FFI.
- No resize event type, signal handler, background task, or global terminal
  state is introduced in this task.
- `vt` remains byte-only and does not depend on terminal size.
- `cmd/*` can use this API later, but this task does not turn demos into public
  layout or screen-management abstractions.

## Acceptance Criteria

- `stdout.window_size()` and `Output::open().window_size()` can return a
  positive row/column pair when a terminal is available.
- Non-tty file outputs return an `OSError`.
- Unix uses `ioctl(TIOCGWINSZ)`.
- Windows uses `GetConsoleScreenBufferInfo`.
- The generated `.mbti` exposes only the intended `WindowSize` type and
  `Output::window_size` method.

## Validation Commands

```sh
moon fmt
moon test .
moon test . # under a PTY
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test .` passed: 11 tests.
- `moon test .` under a PTY passed: 11 tests, including the tty success-path
  window-size query.
- `moon test` passed: 60 tests.
- `moon check` passed.
- `moon info` passed.

## Public API Audit

- `pkg.generated.mbti` exposes the intended additive API only:
  - `WindowSize`
  - `Output::window_size`
- `WindowSize` is `pub struct` so callers can read `rows` and `cols`, but not
  construct values outside the package.
- The C FFI function and output-parameter refs remain package-private.
- No `Input` window-size method, resize event, signal handler, console-event
  loop, or VT dependency was added.
