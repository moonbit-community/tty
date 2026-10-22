# Windows Sidecar Reaping

Status: implemented.

## Goal

Stop `Sidecar::wait` from failing, or trapping on wasm, on Windows when the
sidecar process is already gone, and ship the fix as `0.6.1`.

## Problem

CI on `447a77c` failed in the Windows wasm test step:

```
moonbitlang/async.process/open_pid_handle failed: Native(87)
  at @moonbitlang/async/process.wait_pid
  at @moonbit-community/tty/internal/sidecar.Sidecar::wait
```

- `spawn` starts the sidecar with `@async/process.spawn_orphan`, which closes
  its process handle and returns only the pid.
- `Sidecar::wait` drains the event pipe to EOF and then calls
  `wait_pid(pid)`, which on Windows reopens the process by pid.
- Windows has no zombies. Once the sidecar has exited and no handle refers
  to it, the process object is freed and `OpenProcess` fails with
  `ERROR_INVALID_PARAMETER` (87). On wasm the moonrun host import traps, so
  the error cannot be caught; a freed pid can also be reused by an unrelated
  process.
- The race became visible once `0d4fcb2` embedded the sidecars: the root
  `Tty::open()` test runs without `TTY_SIDECAR`, so on the console-less
  Windows runner it starts the embedded sidecar, which reports an error and
  exits at once, and `spawn`'s cleanup reaps it. It passed on `0d4fcb2` and
  on the `0.6.0` bump PR, and failed on `447a77c`. `0.6.0` is published with
  the race; macOS and Linux are not affected (the exited child stays a
  zombie until `waitpid`).

## Shape

`internal/sidecar/sidecar.mbt` only:

- On Windows (`@async.platform is Windows`, which covers native and wasm),
  `Sidecar::wait` no longer calls `wait_pid`. After the event pipe reaches
  EOF there is nothing to reap.
- The temporary directory holding the executable is removed by a new
  private `remove_temp_dir`. On Windows it retries up to 10 times, 50 ms
  apart, because the image stays locked until the process has fully
  terminated, which can be shortly after its pipe closed. Elsewhere it tries
  once, as before. A directory that still cannot be removed is left behind,
  as before.
- `Sidecar::wait` returns `Unit` instead of the exit status, which Windows
  can no longer provide and no caller used. The `exit : Int32?` field
  becomes `reaped : Bool`.
- Unix keeps reaping with `wait_pid`.

Not done here: holding the process handle from spawn to wait would need
`moonbitlang/async` to return a waitable handle from an orphan spawn; that
belongs upstream.

## Public API diff

- Root package: none.
- `internal/sidecar` (internal, not importable by users):
  `Sidecar::wait(Self) -> Int32` becomes `Sidecar::wait(Self) -> Unit`.

## Invariants

- `wait` is idempotent and not cancellable.
- On Unix the sidecar is still reaped, so no zombie is left.
- The command pipe is closed and the event pipe drained before reaping, so
  the sidecar has run every command sent before `close`.

## Acceptance

- Windows CI passes the native and wasm test steps with the embedded
  sidecars.
- `open and reap the sidecar repeatedly` (`internal/sidecar/locate_test.mbt`)
  opens, closes and reaps the embedded sidecar 20 times. Without a terminal
  every round goes through the fail-fast path that raced; on Windows wasm
  the old code traps there.

## Validation

macOS arm64 with the embedded sidecars from `0d4fcb2`:

- `moon fmt`, `moon info` (only the `internal/sidecar` diff above)
- `moon check --deny-warn`, `moon check --target wasm --deny-warn`
- `moon test --target native internal/sidecar --deny-warn`: 8/8, wasm: 8/8
- `moon test --deny-warn`: 212/212, `moon test --target wasm --deny-warn`:
  207/207
- no `tty-sidecar*` directory left in `$TMPDIR` after the new test
- `git diff --check`

Windows runs only in CI (`windows-latest`, native and wasm steps).
