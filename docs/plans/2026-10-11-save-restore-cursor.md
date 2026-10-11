# DEC Cursor Save/Restore

## Goal

Expose DEC Save Cursor (DECSC) and Restore Cursor (DECRC) through the root `Tty`
command surface, both as methods and as batched `Command` values, without
tracking the saved cursor state.

## Status

Done.

## Context And Decisions

- DECSC and DECRC are fixed two-byte escape sequences:
  - save: `ESC 7`
  - restore: `ESC 8`
- A downstream TUI currently hardcodes both sequences as strings and writes them
  through `Tty::write`, because the root package has no command for them. Its
  use case is probing the real screen size: save the cursor, move to a far
  bottom-right position, read the clamped position back through
  `Tty::query_cursor_position`, then restore.
- Hardcoded strings also cannot join a `Tty::execute` batch, so the command
  needs a `Command` variant as well as a method.
- Use the DEC sequences rather than the SCO pair (`CSI s` / `CSI u`). The SCO
  pair has weaker terminal support, and `CSI u` shares its final byte with the
  kitty keyboard protocol.
- Do not add a scoped `with_saved_cursor` helper. The terminal keeps a single
  saved cursor state, so a second save overwrites the first; a scoped helper
  would suggest nesting that the terminal cannot provide. Callers pair the two
  commands themselves.
- The saved state covers more than the position (SGR attributes, character set,
  origin mode, pending wrap). The package documents this on `Tty::save_cursor`
  and does not model any of it.
- Unsupported terminals can ignore the sequences; no support query is added.

## References Or Standards

- DEC VT100 DECSC (`ESC 7`) and DECRC (`ESC 8`).

## Target Files

- `internal/vt/cursor.mbt`
- `internal/vt/cursor_test.mbt`
- `command.mbt`
- `style.mbt`
- `tty_test.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

Root package additions:

- `Tty::save_cursor(Self) -> Unit`
- `Tty::restore_cursor(Self) -> Unit`
- `Command::SaveCursor`
- `Command::RestoreCursor`

Internal VT package additions:

- `save_cursor : Bytes`
- `restore_cursor : Bytes`

No new public type, parser state, input event, platform backend, or capability
query is proposed.

## Invariants

- `Tty` remains the public output-command surface.
- `internal/vt` remains byte-sequence-only and does not own output streams.
- The package does not remember, infer, or stack saved cursor state.
- Cursor save/restore does not add a screen model, renderer, layout layer, or
  terminal-emulator state.

## Acceptance Criteria

- Internal VT helpers emit `ESC 7` and `ESC 8`.
- Root command methods and `Tty::execute` write the same bytes through `Tty`.
- Generated `.mbti` diffs contain only the intended API additions.

## Validation Commands

- `moon fmt` passed; `moon fmt --check` passed.
- `moon check --deny-warn` passed.
- `moon test internal/vt` passed: 25 tests.
- `moon test .` passed: 28 tests.
- `moon test --deny-warn` passed.
- `moon info` passed and regenerated intended `.mbti` entries.
- `git diff --check` passed.

Validation ran on macOS only. The sequences were not exercised against a real
terminal in this task; the tests assert the emitted bytes through a pipe-backed
`Tty`.

## Public API Audit

- Root `Tty` now exposes `save_cursor` and `restore_cursor` for callers that
  need to return the cursor to a known place after a temporary move.
- Root `Command` gains `SaveCursor` and `RestoreCursor` so the same operations
  can join a `Tty::execute` batch. `Command` is `pub(all)`, so the new variants
  break downstream code that matches it exhaustively. `Command` is intended to
  be constructed by callers rather than matched. This is the first variant
  addition since `Command` was introduced.
- Internal VT exposes `save_cursor` and `restore_cursor` byte constants for the
  root command methods.
- No public parser state, platform handle, input event, wrapper type, mutable
  field, or terminal state model was added.
- The generated `.mbti` diff was reviewed and contains only the intended root
  and internal VT additions.

## Result Notes

- Added fixed DECSC/DECRC byte constants, root write-through methods, and
  `Command` variants.
- Added an internal VT sequence test and a root pipe-backed test covering both
  the methods and a `Tty::execute` batch.
- Updated README, architecture notes, and the execution board.

## Open Questions

- None.
