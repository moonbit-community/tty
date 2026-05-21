# Tty Open RawFd Backend

## Goal

Make `Tty::open` avoid macOS `kqueue` registration failures when opening the
controlling terminal via `/dev/tty`.

## Status

Done.

## Context And Decisions

- `@async/fs.open("/dev/tty", mode=ReadWrite)` classifies `/dev/tty` as a
  character device and treats it as pollable.
- On macOS, registering `/dev/tty` with the current async kqueue backend fails
  for the default `EVFILT_READ` and `EVFILT_WRITE` registrations with `EINVAL`.
- `@async/raw_fd.RawFd` chooses its async backend from the fd's current
  nonblocking flag. A normal blocking fd should therefore use the worker path
  instead of kqueue.
- Keep the public API shape unchanged. This task only changes the Unix
  implementation of `Tty::open`.
- Windows behavior is left unchanged for this trial.

## Target Files

- `docs/plan.md`
- `docs/plans/2026-05-21-tty-open-raw-fd.md`
- `moon.pkg`
- `tty_unix.mbt`
- `tty_open.c`
- `pkg.generated.mbti`

## Public API Changes

- No intended public API change.
- `Tty::open` remains the public constructor for the controlling terminal.

## Invariants

- `Tty::open` returns one coordinated terminal handle for input and output.
- The fd opened by `Tty::open` is owned by the returned `Tty` and is closed by
  `Tty::close`.
- The input side still implements `@async/io.Reader` with its own reader buffer.
- The output side still implements `@async/io.Writer`.
- The implementation must not make `/dev/tty` nonblocking before constructing
  `RawFd`.

## Acceptance Criteria

- `Tty::open` no longer uses `@async/fs.open` on Unix.
- A normal `moon run examples/agent` reaches terminal setup without
  `OSError("poll_register: Invalid argument")` on macOS.
- Existing unit tests and package checks continue to pass.
- `pkg.generated.mbti` has no public API churn beyond regenerated formatting.

## Validation Commands

```sh
moon fmt
moon test .
moon check examples/agent
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test .` passed: 11 tests.
- `moon check examples/agent` passed.
- `moon test` passed: 89 tests.
- `moon check` passed.
- `moon info` passed with no `pkg.generated.mbti` diff.
- `git diff --check` passed.
- Manual PTY smoke: `moon run examples/agent` launched the agent UI without
  `OSError("poll_register: Invalid argument")`; Ctrl-C exited cleanly.

## Public API Audit

- No public root API shape changed.
- `Tty::open` remains public and keeps the same signature.
- The new `ControllingTerminal` wrapper is private and does not appear in
  `pkg.generated.mbti`.
