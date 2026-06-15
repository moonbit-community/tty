# Move Color Encoding To Internal VT

## Goal

Move the VT byte encoding for semantic color values out of root `style.mbt` and
into `moonbit-community/tty/internal/vt`, while keeping root `Tty` color command
methods as the public user-facing API.

## Status

Done.

## Context And Decisions

- The root package currently owns private helpers that map `@color.Color` values
  to SGR byte sequences.
- `internal/vt` already owns pure VT byte construction for cursor, screen,
  erase, scroll, mode, and fixed SGR attribute commands.
- `color/` remains the semantic color value package and should not construct
  terminal byte sequences or write to streams.
- `internal/vt` may depend on `moonbit-community/tty/color` because it is an
  implementation package used by root `Tty` methods, not downstream API.
- Root `Tty` methods remain command-style methods that only write generated
  bytes and do not track terminal style state.

## References Or Standards

- ECMA-48 SGR parameters:
  - SGR 0 resets all SGR style attributes.
  - SGR 30-37 and 90-97 set basic and bright foreground colors.
  - SGR 40-47 and 100-107 set basic and bright background colors.
  - SGR 38;5;n and 48;5;n set indexed foreground/background colors.
  - SGR 38;2;r;g;b and 48;2;r;g;b set truecolor foreground/background colors.
  - SGR 39 and 49 reset foreground/background colors to terminal defaults.

## Target Files

- `docs/plans/2026-06-15-move-color-encoding-to-internal-vt.md`
- `docs/architecture.md`
- `internal/vt/moon.pkg`
- `internal/vt/sgr.mbt`
- `internal/vt/sgr_test.mbt`
- `internal/vt/pkg.generated.mbti`
- `style.mbt`
- `tty_wbtest.mbt`

## Public API Changes

Root package public API should remain unchanged:

- `pkg.generated.mbti` should have no diff.
- `color/pkg.generated.mbti` should have no diff.

Internal VT package API is expected to gain:

- `reset_style : Bytes`
- `reset_foreground : Bytes`
- `reset_background : Bytes`
- `set_foreground(@color.Color) -> Bytes`
- `set_background(@color.Color) -> Bytes`

The internal VT package `.mbti` is not downstream public API, but it is still
reviewed as an internal package boundary.

## Invariants

- `internal/vt` remains pure byte construction and does not write to or own an
  output stream.
- `internal/vt` does not import or depend on the root `tty` package.
- `color/` remains value-only and does not construct SGR bytes.
- Root `Tty` color methods keep their signatures and behavior.
- Numeric indexed and RGB channels remain clamped to `0..255` at the SGR
  encoding boundary.

## Acceptance Criteria

- The root `style.mbt` no longer contains color-to-SGR encoding helpers.
- Root `Tty::set_foreground`, `Tty::set_background`, `Tty::reset_foreground`,
  `Tty::reset_background`, and `Tty::reset_style` delegate to `@vt`.
- `internal/vt` tests cover default, basic, bright, indexed, truecolor, and
  reset color sequences.
- Existing root pipe tests still prove `Tty` writes the same command bytes.

## Validation Commands

```sh
moon fmt
moon test internal/vt
moon test .
moon check
moon info
moon test
git diff --check
```

## Public API Audit

- Root `pkg.generated.mbti` has no diff.
- `color/pkg.generated.mbti` has no diff.
- `internal/vt/pkg.generated.mbti` gained only the planned `@color` import,
  reset byte constants, and foreground/background color SGR constructors.
- No root private helper leaked into downstream public API.
- The internal VT `.mbti` diff was reviewed after `moon info`.

## Result Notes

- Moved semantic color SGR encoding helpers from root `style.mbt` into
  `internal/vt/sgr.mbt`.
- Root `Tty` color command methods now delegate to `@vt.set_foreground`,
  `@vt.set_background`, `@vt.reset_foreground`, `@vt.reset_background`, and
  `@vt.reset_style`.
- Moved direct color encoding tests from root white-box tests to
  `internal/vt/sgr_test.mbt`; root pipe tests still cover end-to-end command
  bytes.
- `moon fmt` passed.
- `moon test internal/vt` passed: 20 tests.
- `moon test .` passed: 24 tests.
- `moon check` passed.
- `moon info` passed.
- `moon test` passed: 165 tests.
- `git diff --check` passed.

## Open Questions

- None after approval on 2026-06-15.
