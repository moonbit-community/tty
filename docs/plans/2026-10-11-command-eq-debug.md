# Eq And Debug For Command And Root Value Types

## Goal

Let callers compare and debug-print `Command` values and the other root value
types, so code built on `Tty::execute` can assert on the commands it produces.

## Status

Done.

## Context And Decisions

- `Command` is inert data that only writes bytes when passed to `Tty::execute`,
  but it derived nothing. A caller that builds a command batch (for example a
  renderer that diffs two frames into commands) could not compare the batch with
  an expected one or snapshot it; it could only execute it against a pipe and
  inspect raw escape bytes.
- Derive `Eq` and `Debug` on `Command`. Every payload already supports both:
  `Int`, `StringView`, and `@color.Color`, except `KeyboardEnhancementFlags`,
  which had `Eq` only.
- Add `Debug` to `KeyboardEnhancementFlags` as the prerequisite. It stays an
  opaque newtype; the derived form prints the raw flag bits, for example
  `KeyboardEnhancementFlags(1)`.
- Add `Debug` to `Event`, `WindowSize`, `CursorPosition`, and
  `MouseTrackingMode` in the same change. They already derive `Eq`, the
  `@input` and `@color` value types already derive both, and callers testing
  input handling need to print `Event` the same way.
- Do not add `Show`. `Debug` is the diagnostic form; none of these types has a
  user-facing text representation.
- The root package now imports `moonbitlang/core/debug` outside tests, matching
  `color` and `input`.

## References Or Standards

- None. This change emits no terminal bytes.

## Target Files

- `command.mbt`
- `tty.mbt`
- `size.mbt`
- `style.mbt`
- `moon.pkg`
- `tty_test.mbt`
- `tty_wbtest.mbt`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

Root package additions:

- `Command`: `derive(Eq, Debug)`, exposing `equal`, `not_equal`, `to_repr`
- `KeyboardEnhancementFlags`: `Debug`, exposing `to_repr`
- `Event`: `Debug`, exposing `to_repr`
- `WindowSize`: `Debug`, exposing `to_repr`
- `CursorPosition`: `Debug`, exposing `to_repr`
- `MouseTrackingMode`: `Debug`, exposing `to_repr`

No new type, variant, field, or function beyond the derived trait methods.

## Invariants

- `Command` stays inert data; deriving traits adds no state and no I/O.
- `KeyboardEnhancementFlags` stays opaque: no field access or constructor is
  added.
- `Tty` and `State` gain nothing; they are handles, not values.

## Acceptance Criteria

- Two equal command batches compare equal, and batches that differ in a variant
  or payload compare unequal.
- `debug_inspect` prints `Command`, `Event`, `MouseTrackingMode`,
  `CursorPosition`, and `WindowSize` values.
- Generated `.mbti` diffs contain only the derived trait methods and the
  `moonbitlang/core/debug` import.

## Validation Commands

- `moon fmt` passed; `moon fmt --check` passed.
- `moon check --deny-warn` passed.
- `moon test .` passed: 31 tests.
- `moon test --deny-warn` passed.
- `moon info` passed and regenerated intended `.mbti` entries.
- `git diff --check` passed.

Validation ran on macOS only.

## Public API Audit

- Added derived `Eq` and `Debug` methods on `Command`, and derived `Debug`
  methods on `KeyboardEnhancementFlags`, `Event`, `WindowSize`,
  `CursorPosition`, and `MouseTrackingMode`.
- External consumer story: assert on and snapshot command batches and decoded
  root events in downstream tests.
- Not breaking: every change is an added trait implementation.
- The debug form of `KeyboardEnhancementFlags` exposes its raw bits, which
  `KeyboardEnhancementFlags::bits` already exposes.
- No internal helper, parser state, platform handle, or mutable field leaked
  into public API.
- The generated `.mbti` diff was reviewed and contains only the intended
  additions.

## Result Notes

- Added the derives and the matching `pub extend` lines next to the existing
  `Eq` ones.
- Added black-box tests for `Command` equality and debug output, and for
  `Event` and `MouseTrackingMode` debug output; added a white-box test for
  `CursorPosition` and `Event::Resize`, which black-box tests cannot construct.
- Updated architecture notes and the execution board.

## Open Questions

- None.
