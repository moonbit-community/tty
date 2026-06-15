# Output Write Lock

## Goal

Serialize `Tty` output writes so a single `Tty::write` / `Tty::write_string`
call lands on the terminal atomically with respect to other concurrent writers,
without the caller having to coordinate access. Keep the locking primitive
internal and the public `Tty` shape opaque.

## Status

Done.

## Context And Decisions

- `moonbitlang/async` is a single-threaded cooperative runtime, so there are no
  data races, but a logical write can still interleave: `@async/io.Writer.write`
  loops over `write_once` syscalls with suspension points between them, letting a
  second writer splice its bytes into the first writer's escape sequences.
- A binary semaphore (`Semaphore(1)`) is the smallest primitive that makes a
  single write critical section atomic. The `Semaphore` type already exists in
  the pinned `moonbitlang/async@0.19.1`, so no dependency bump is required.
- Wrap the semaphore in a small internal `lock` package (`Lock`) instead of
  exposing the async semaphore directly, so the locking contract is named and
  documented in one place and the `with_lock` combinator owns acquire/release
  pairing.
- `with_lock` releases via `defer`, registered only after `acquire` succeeds, so
  a cancelled `acquire` never releases a lock it does not hold and a failing
  action still releases.
- Locking granularity is per call. A method that issues several `write`s (for
  example `enable_mouse`) is a sequence of atomic writes, not one atomic unit;
  frame-level atomicity remains the caller's responsibility (assemble one buffer
  per write). This is documented on `write` / `write_string`.
- A bump to `moonbitlang/async@0.19.4` was attempted and reverted: it regressed
  the Windows `Tty` write path (`tests/open` `Tty::open` timed out on
  windows-latest) and is unnecessary because `0.19.1` already provides the
  `Semaphore` API used here.

## References Or Standards

- `moonbitlang/async/semaphore` `Semaphore` (binary semaphore as a mutex).

## Target Files

- `internal/lock/moon.pkg`
- `internal/lock/lock.mbt`
- `internal/lock/lock_test.mbt`
- `tty.mbt`
- `win32_input_wbtest.mbt`
- `moon.pkg`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

New internal package `moonbit-community/tty/internal/lock`:

- `Lock` (opaque struct)
- `Lock::new() -> Lock`
- `Lock::acquire(Self) -> Unit` (async)
- `Lock::try_acquire(Self) -> Bool`
- `Lock::release(Self) -> Unit`
- `Lock::with_lock[X](Self, async () -> X) -> X` (async)

Root package: no public API change. `Tty` gains a private `write_lock : @lock.Lock`
field; `Tty::write` and `Tty::write_string` keep their existing signatures.

No new public type, parser state, input event, platform backend, dependency, or
capability query is added.

## Invariants

- Every byte written to the terminal output stream goes through `Tty::write` or
  `Tty::write_string`, both of which hold `write_lock` for the duration of the
  underlying writer call.
- `fd()`-based operations (`size.mbt`, `state.mbt`) are independent atomic
  syscalls and are intentionally not serialized by `write_lock`.
- `with_lock` releases the lock on both the normal and the failure path, and
  never releases when `acquire` was cancelled before taking the lock.
- The `lock` package is internal and exposes no public mutable fields; `Lock` is
  opaque.

## Acceptance Criteria

- Concurrent critical sections guarded by `with_lock` never overlap, even when
  the holder suspends.
- `with_lock` releases the lock when its action fails.
- Root `.mbti` is unchanged (the new field is private).
- Generated `.mbti` for the `lock` package exposes only the intended methods and
  no fields.

## Validation Commands

- `moon fmt`
- `moon test internal/lock`
- `moon test .`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Public API Audit

- New `internal/lock/pkg.generated.mbti` exposes `Lock` as an opaque struct
  (`// private fields`) plus `new`, `acquire`, `try_acquire`, `release`, and
  `with_lock`. No public fields are exposed.
- Root `pkg.generated.mbti` is unchanged: `write_lock` is a private field and
  `Tty::write` / `Tty::write_string` signatures are unchanged.
- No public type, mutable field, parser state, input event, platform handle,
  backend selection, dependency, or capability query was added.
- `moonbitlang/async` stays pinned at `0.19.1`; no dependency version change.
- Generated `.mbti` files were reviewed after `moon info`.

## Result Notes

- Added the internal `lock` package wrapping `Semaphore(1)` with a `with_lock`
  combinator that pairs acquire/release through `defer`.
- Routed `Tty::write` / `Tty::write_string` through `write_lock.with_lock(...)`
  and initialized `write_lock` in both the Windows and non-Windows constructors.
- Updated the Windows white-box `Tty` literal in `win32_input_wbtest.mbt` to set
  the new field.
- Per-call atomicity only; multi-write command methods are not wrapped as a
  single unit. Documented the build-one-buffer idiom for frame-level atomicity.

## Validation Results

- `moon fmt` passed.
- `moon test internal/lock` passed: 2 tests.
- `moon test` passed: 165 tests.
- `moon check` passed.
- `moon info` passed and regenerated the intended `.mbti` entries.
- CI passed on ubuntu-latest, macos-latest, and windows-latest.
- generated `.mbti` diff reviewed.
- `git diff --check` passed.

## Open Questions

- Whether selected multi-write command methods (for example mouse enable/disable)
  should be wrapped in `with_lock` for group atomicity, or batched into a single
  buffer. Deferred; current contract is per-call atomicity.
- Revisiting `moonbitlang/async@0.19.4`: it regresses the Windows `Tty` write
  path and needs separate investigation before any future bump.
