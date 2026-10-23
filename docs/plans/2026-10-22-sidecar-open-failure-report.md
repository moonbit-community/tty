# Sidecar Open Failure Report

Status: implemented.

## Goal

Make a failed `@sidecar.open()` (and so `Tty::open()`) report why the
sidecar failed. Without a controlling terminal `0.6.2` raises

```
OSError("@fs.rmdir(): \"/tmp/tty-sidecar.…\": No such file or directory")
```

instead of the sidecar's own error.

## Problem

Two bugs are stacked; the outer one hides the inner one.

1. Double removal of the temporary directory. `open` registers
   `errdefer @async/fs.rmdir(dir, recursive=true)` around `spawn`. When
   `spawn` fails after starting the process, its own `errdefer` reaps the
   sidecar through `Sidecar::wait`, which already removes `temp_dir`. The
   second `rmdir` in `open` then raises `ENOENT`, and that error replaces
   the one `spawn` was propagating. Only the embedded-sidecar path is
   affected; `TTY_SIDECAR` has no temporary directory.
2. The POSIX sidecar never sends its startup error. `write_out` only queues
   frames, which the main loop flushes. When `open("/dev/tty")` fails,
   `main` queues the error frame and returns, so the host reads EOF and
   raises `ProtocolError("sidecar exited before saying hello")`. The Windows
   `write_out` writes to the pipe directly and is not affected.

Observed without a controlling terminal on macOS arm64:

| state | `open()` raises |
|---|---|
| `0.6.2` | `OSError("@fs.rmdir(): …: No such file or directory")` |
| bug 1 fixed | `ProtocolError("sidecar exited before saying hello")` |
| both fixed | `SidecarError("open /dev/tty failed: Device not configured")` |

## Shape

- `internal/sidecar/locate.mbt`: the `errdefer` in `open` calls the existing
  `remove_temp_dir`, which ignores a failed removal (and retries on
  Windows), instead of a raising `rmdir`.
- `sidecar/sidecar.c`: flush the queued error frame with the existing
  `flush_out` before returning when `/dev/tty` cannot be opened. stdout is
  still blocking at that point (`O_NONBLOCK` is set later), so the frame is
  written in full.
- `internal/sidecar/locate_test.mbt`: a test that `open` never raises an
  `ENOENT` `OSError`.

No new types, helpers, fields or files besides this plan.

## Public API diff

None. `moon info` leaves every `pkg.generated.mbti` unchanged.

## Invariants

- The temporary directory is still removed on every failure path of `open`
  and by `Sidecar::wait`.
- Errors raised by `spawn` reach the caller unchanged.

## Acceptance

- `a failed open reports the sidecar's failure` fails on `0.6.2` (it
  reports the `rmdir` error) and passes with the fix.
- With a sidecar built from the patched `sidecar.c` (`TTY_SIDECAR`), `open`
  without a terminal raises `SidecarError("open /dev/tty failed: …")`.
- The embedded sidecars only pick up the `sidecar.c` change once the
  `sidecars` workflow regenerates `internal/sidecar/sidecars.generated.mbt`
  on `main`; until then the embedded path reports the `ProtocolError`.

## Validation

macOS arm64, no controlling terminal unless noted:

- `moon fmt`, `moon info`: no `.mbti` diff
- `moon check --deny-warn`, `moon check --target wasm --deny-warn`
- `moon test --deny-warn`: 213/213, `moon test --target wasm --deny-warn`:
  208/208
- `moon test internal/sidecar --target native --deny-warn`: 9/9; the new
  test fails on `0.6.2` with the `rmdir` `ENOENT`
- `cc -Wall -Wextra -O2 sidecar/sidecar.c`: no warnings;
  `TTY_SIDECAR=<that build> moon test internal/sidecar --target native`:
  9/9, and `open` raises `SidecarError("open /dev/tty failed: Device not
  configured")`
- under a pty (`script -q /dev/null …`), embedded and `TTY_SIDECAR`:
  `moon test internal/sidecar --target native`: 9/9
- no `tty-sidecar*` directory left in `/tmp`
- `git diff --check`

Windows runs only in CI.
