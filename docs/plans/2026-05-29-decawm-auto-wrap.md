# DECAWM Auto Wrap Mode

## Goal

Expose DEC auto wrap mode (DECAWM, private mode 7) through the root `Tty`
command surface, without adding terminal-emulator state or capability probing.

## Status

Done.

## Context And Decisions

- DECAWM is controlled with DEC private mode 7:
  - enable: `CSI ? 7 h`
  - disable: `CSI ? 7 l`
- This is an output-side terminal mode switch. It does not affect the input
  event model.
- Do not add a scoped `with_auto_wrap` helper. The package does not track the
  previous terminal mode state, and forcing a fixed restore value could undo a
  caller or terminal preference.
- Unsupported terminals can ignore the mode switch; no support query is added.

## References Or Standards

- DEC private mode 7, commonly named DECAWM.

## Target Files

- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

Root package additions:

- `Tty::enable_auto_wrap(Self) -> Unit`
- `Tty::disable_auto_wrap(Self) -> Unit`

Internal VT package additions:

- `enable_auto_wrap : Bytes`
- `disable_auto_wrap : Bytes`

No new public type, parser state, input event, platform backend, or capability
query is proposed.

## Invariants

- `Tty` remains the public output-command surface.
- `internal/vt` remains byte-sequence-only and does not own output streams.
- The package does not remember or infer terminal auto-wrap state.
- DECAWM support does not add a screen model, renderer, layout layer, or
  terminal-emulator state.

## Acceptance Criteria

- Internal VT helpers emit `CSI ? 7 h` and `CSI ? 7 l`.
- Root command helpers write the same bytes through `Tty`.
- Generated `.mbti` diffs contain only the intended API additions.

## Validation Commands

- `moon fmt` passed.
- `moon test internal/vt` passed: 17 tests.
- `moon test .` passed: 24 tests.
- `moon check` passed.
- `moon info` passed and regenerated intended `.mbti` entries.
- `git diff --check` passed.

## Public API Audit

- Root `Tty` now exposes `enable_auto_wrap` and `disable_auto_wrap` for callers
  that need to control DECAWM directly.
- Internal VT exposes `enable_auto_wrap` and `disable_auto_wrap` byte constants
  for root command methods.
- No public parser state, platform handle, input event, wrapper type, mutable
  field, or terminal state model was added.
- The generated `.mbti` diff was reviewed and contains only the intended root
  and internal VT additions.

## Result Notes

- Added fixed DECAWM byte constants and root write-through helpers.
- Added internal VT sequence tests and root pipe-backed command tests.
- Updated README, architecture notes, and the execution board.

## Open Questions

- None.
