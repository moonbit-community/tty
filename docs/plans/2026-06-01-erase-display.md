# Display Erase Commands

## Goal

Add root `Tty` command helpers for `CSI 2 J` and `CSI 3 J`, while keeping VT
byte construction internal and avoiding any terminal screen or scrollback state
model.

## Status

Done.

## Context And Decisions

- `CSI 2 J` is Erase in Display (ED) mode 2. It clears the visible display.
- `CSI 3 J` is the common xterm extension for clearing saved lines or
  scrollback.
- Avoid the name `erase_display_all` because it can imply that `CSI 2 J` also
  clears scrollback.
- Use the shorter approved root method names:
  - `erase_display`
  - `erase_scrollback`
- These are output-side commands only. Unsupported terminals may ignore
  `CSI 3 J`; no support query is added.

## References Or Standards

- ECMA-48 Erase in Display (ED), `CSI Ps J`.
- xterm-compatible `CSI 3 J` saved-lines erase extension.

## Target Files

- `internal/vt/erase.mbt`
- `internal/vt/erase_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `README.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

Root package additions:

- `Tty::erase_display(Self) -> Unit`
- `Tty::erase_scrollback(Self) -> Unit`

Internal VT package additions:

- `erase_display : Bytes`
- `erase_scrollback : Bytes`

No new public type, parser state, input event, platform backend, dependency, or
capability query is proposed.

## Invariants

- `Tty` remains the public output-command surface.
- `internal/vt` remains byte-sequence-only and does not own output streams.
- The package does not remember, infer, or expose terminal display state.
- The package does not model or manage terminal scrollback.

## Acceptance Criteria

- Internal VT helpers emit `CSI 2 J` and `CSI 3 J`.
- Root command helpers write the same bytes through `Tty`.
- Generated `.mbti` diffs contain only the intended API additions.
- README mentions display and scrollback erase as output commands.

## Validation Commands

- `moon fmt`
- `moon test internal/vt`
- `moon test .`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Public API Audit

- Root `.mbti` adds only `Tty::erase_display` and
  `Tty::erase_scrollback`.
- Internal VT `.mbti` adds only the `erase_display` and `erase_scrollback`
  byte constants used by root command methods.
- No public type, mutable field, parser state, input event, platform handle,
  backend selection, dependency, or capability query was added.
- Generated `.mbti` files were reviewed after `moon info`.

## Result Notes

- Added fixed ED byte constants for `CSI 2 J` and `CSI 3 J`.
- Added root write-through helpers on `Tty`.
- Added internal VT byte tests and extended the root pipe-backed terminal
  command test to cover both new methods.
- Updated README output-command wording and the execution board.
- Real terminal clear behavior needs a terminal emulator with observable screen
  state; pipe and PTY tests only verify byte traffic. No terminal-emulator
  integration test was added for this task.

## Validation Results

- `moon fmt` passed.
- `moon test internal/vt` passed: 18 tests.
- `moon test .` passed: 24 tests.
- `moon test` passed: 146 tests.
- `moon check` passed.
- `moon info` passed and regenerated intended `.mbti` entries.
- generated `.mbti` diff reviewed.
- `git diff --check` passed.

## Open Questions

- None.
