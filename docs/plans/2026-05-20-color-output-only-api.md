# Color Output-Only API

## Goal

Make `tonyfettes/tty/color` a semantic color value package only. Move color
sequence construction behind root `Output` command methods, while keeping
low-level raw SGR byte construction in `tonyfettes/tty/vt`.

## Status

Done.

## Context And Decisions

- `Color` and `BasicColor` are user-facing semantic values.
- `foreground`, `background`, and reset byte constants are terminal commands,
  not color model operations.
- Public command-style color operations should be methods on `Output`.
- Users who need raw VT bytes can use `@vt.sgr1`, `@vt.sgr3`, and `@vt.sgr5`.
- Color capability detection remains out of scope.

## Target Files

- `color/moon.pkg`
- `color/color.mbt`
- `color/color_test.mbt`
- `color/pkg.generated.mbti`
- `style.mbt`
- `tty_wbtest.mbt`
- `pkg.generated.mbti`
- `cmd/color/*`
- `cmd/agent/*`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-color-output-only-api.md`

## Public API Changes

Remove from `tonyfettes/tty/color`:

- `foreground(Color) -> Bytes`
- `background(Color) -> Bytes`
- `reset_style : Bytes`
- `reset_foreground : Bytes`
- `reset_background : Bytes`

Keep in `tonyfettes/tty/color`:

- `BasicColor`
- `Color`

Keep root `Output` methods:

- `set_foreground(@color.Color)`
- `set_background(@color.Color)`
- `reset_foreground()`
- `reset_background()`
- `reset_style()`

## Invariants

- `color/` does not import `vt` or construct byte sequences.
- `vt` remains byte-only and does not import root `tty`.
- Root `Output` methods write SGR bytes but do not track terminal style state.
- Existing command demos use `Output` methods for color commands.

## Acceptance Criteria

- Repository code has no calls to `@color.foreground`, `@color.background`, or
  `@color.reset_*`.
- `color/pkg.generated.mbti` exposes only color value types.
- Root tests cover the SGR encoding still used by `Output`.
- `cmd/color` and `cmd/agent` compile with the narrower color package.

## Validation Commands

```sh
moon fmt
moon test color
moon test .
moon check cmd/color
moon check cmd/agent
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test color` passed: 1 test.
- `moon test .` passed: 14 tests.
- `moon check cmd/color` passed.
- `moon check cmd/agent` passed.
- `moon test` passed: 86 tests.
- `moon check` passed.
- `moon info` passed.

## Public API Audit

- Removed all public byte-sequence values and functions from
  `tonyfettes/tty/color`.
- Kept `BasicColor` and `Color` public and constructible.
- Kept root `Output` color command methods unchanged.
- Kept `vt.sgr1`, `sgr3`, and `sgr5` as the raw SGR byte-construction API.
