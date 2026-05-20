# Tty Reader Writer Traits

## Goal

Prototype a trait-based terminal handle model so `Tty::new` can accept any
reader/writer pair with terminal file descriptors instead of requiring the root
`Input`/`Output` enum wrappers.

## Status

Done.

## Context And Decisions

- `moonbitlang/async/io` already provides open `Reader` and `Writer` traits for
  byte streams.
- Terminal operations also need file descriptors and close semantics, so the
  root package should define terminal-handle traits on top of async I/O.
- `Tty` should not become a generic type. Keep `Tty` opaque and erase concrete
  handles behind trait objects internally.
- Root `Input` and `Output` wrappers remain for this step as compatibility and
  low-level convenience types. Removing them should be a separate follow-up if
  the trait model holds.

## Target Files

- `tty.mbt`
- `tty_handle.mbt`
- `state.mbt`
- `size.mbt`
- `style.mbt`
- `tty_unix.mbt`
- `tty_wbtest.mbt`
- `pkg.generated.mbti`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-tty-reader-writer-traits.md`

## Public API Changes

- Add public open trait `Reader : @io.Reader` with `fd` and `close`.
- Add public open trait `Writer : @io.Writer` with `fd` and `close`.
- Add public generic `Tty::new[I : Reader, O : Writer](I, O) -> Tty`.
- Keep `Tty::stdio()` and `Tty::open()` as convenience constructors.
- Keep root `Input` and `Output` wrappers in this step.

## Invariants

- `Tty` remains opaque and non-generic.
- Raw-mode operations use the reader-side file descriptor.
- Window-size queries use the writer-side file descriptor.
- `Tty::close` closes both sides; stdio trait implementations make close a
  no-op. Shared-handle construction is valid when the handle's `close` is
  idempotent, as with `@async/fs.File`.
- Normal event decoding and terminal response parsing still share one
  `EventReader`.

## Acceptance Criteria

- `Tty::new` can be called with `@async/fs.File` handles.
- `Tty::stdio` can be built directly from `@async/stdio.stdin` and
  `@async/stdio.stdout`.
- Unix `Tty::open` opens `/dev/tty` once in read-write mode and uses that file
  as both the terminal reader and writer.
- Existing root tests and examples continue to pass.
- Root `.mbti` shows the new traits and generic constructor without making
  `Tty` generic.

## Validation Commands

```sh
moon fmt
moon test .
moon check examples/agent
moon test
moon check
moon info
git diff --check
```

## Validation Results

- `moon fmt` passed.
- `moon test .` passed: 15 tests.
- `moon check examples/agent` passed.
- `moon test` passed: 93 tests.
- `moon check` passed.
- `moon info` passed and regenerated public interfaces.
- `git diff --check` passed.

## Public API Audit

- Root `.mbti` now exposes public open `Reader : @io.Reader` and
  `Writer : @io.Writer` traits with `fd` and `close`.
- Root `.mbti` now exposes `Tty::new[I : Reader, O : Writer](I, O) -> Tty`.
- `Tty` remains opaque and non-generic in the public API.
- Public trait impls are provided for `@async/fs.File`,
  `@async/stdio.Input`, and `@async/stdio.Output`.
- Root `Input` and `Output` wrappers remain public low-level convenience
  handles, but `Tty` no longer stores them internally.
- Unix `Tty::open` lives in `tty_unix.mbt`, opens `/dev/tty` once in read-write
  mode, and passes the same `@async/fs.File` as both reader and writer.
