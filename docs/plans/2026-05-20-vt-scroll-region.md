# VT Scroll Region And Reverse Index

## Goal

Add byte-only VT helpers for setting/resetting the scrolling margins and for
Reverse Index. These are the terminal primitives needed before a demo can keep
an input area at the bottom while letting output above it scroll.

## Status

Done.

## Context And Decisions

- DECSTBM sets the top and bottom scrolling margins using `CSI top ; bottom r`.
- Resetting the margins uses `CSI r`.
- Reverse Index uses `ESC M`.
- These helpers belong in `tonyfettes/tty/vt` because they are pure byte
  sequences.
- This task does not write to an `Output`, query terminal size, track cursor
  position, maintain scrollback, or introduce a screen model.
- Resize-aware region selection belongs to callers or a later demo task.

## Target Files

- `vt/scroll.mbt`
- `vt/scroll_test.mbt`
- `vt/pkg.generated.mbti`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-vt-scroll-region.md`

## Public API Changes

Add:

```mbt
pub fn set_top_bottom_margins(top : Int, bottom : Int) -> Bytes
pub let reset_top_bottom_margins : Bytes
pub let reverse_index : Bytes
```

Consumer story:

- Callers can define the terminal rows that are allowed to scroll.
- Callers can reset the terminal back to the full-screen scrolling region.
- Callers can emit RI when positioned at the top scrolling margin.

Parameter rules:

- `top` and `bottom` are 1-based inclusive terminal rows.
- Values below 1 are treated as 1.
- If `bottom < top`, `bottom` is treated as `top`.

This is additive and not breaking.

Naming follows local ultraviolet's dependency `github.com/charmbracelet/x/ansi`:
the preferred helper there is `SetTopBottomMargins`, `DECSTBM` is an alias, and
the older `SetScrollingRegion` name is deprecated. RI is named `ReverseIndex`.

## Invariants

- `vt` remains byte-only and does not depend on root `Output`.
- No terminal state is stored.
- No terminal size is queried in `vt`.
- No screen rendering, layout, widget, or scrollback abstraction is introduced.
- Generated `.mbti` should expose only the three intended public values.

## Acceptance Criteria

- `set_top_bottom_margins(1, 24)` emits `ESC [ 1 ; 24 r`.
- Low row values are clamped to valid 1-based parameters.
- `reset_top_bottom_margins` emits `ESC [ r`.
- `reverse_index` emits `ESC M`.
- Tests cover the new byte sequences.

## Validation Commands

```sh
moon fmt
moon test vt
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test vt` passed: 9 tests.
- `moon test` passed: 66 tests.
- `moon check` passed.
- `moon info` passed.

## Public API Audit

- `vt/pkg.generated.mbti` exposes only the intended additive VT helpers:
  - `set_top_bottom_margins`
  - `reset_top_bottom_margins`
  - `reverse_index`
- No root package, `input`, or command package public API changed for this VT
  task.
- No output stream ownership, terminal size query, screen state, or scrollback
  model was added to `vt`.
