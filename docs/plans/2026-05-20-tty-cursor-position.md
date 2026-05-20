# Tty Cursor Position Probe

## Goal

Introduce a narrow root-package `Tty` handle for operations that coordinate a
terminal input stream and output stream, starting with cursor position report
queries. Use it to move `examples/agent` from relative composer repainting
toward the Codex-style primary-screen model: finalized transcript rows are
inserted above a known inline viewport while the composer is redrawn in place.

## Status

Done.

## Context And Decisions

- `Input` and `Output` remain the low-level wrappers for standalone reads,
  writes, raw mode, styles, and window-size queries.
- `Tty` is a narrow coordination handle for one terminal. It is not a screen
  renderer, terminal emulator, widget tree, or TUI framework.
- Cursor position report is a terminal request/response protocol: write
  `CSI 6 n`, then read `CSI row ; col R` from the same terminal input stream.
- Cursor position reports are not user input events. They should not be added
  to `@input.Event`; otherwise normal event loops would have to handle internal
  terminal responses and CPR could be confused with CSI key sequences.
- `EventReader` owns the byte buffer, so CPR response parsing belongs beside
  input decoding. A dedicated method can consume a matching CPR response while
  preserving unrelated buffered input for later `read_event` calls.
- `vt` remains byte-only and only adds the request sequence constant.
- `examples/agent` may keep demo-local editor and transcript rendering state,
  but should use `Tty` so cursor probing and event decoding share one input
  buffer.

## Target Files

- `tty.mbt`
- `tty_unix.mbt`
- `style.mbt`
- `input/decoder.mbt`
- `input/decoder_test.mbt`
- `input/pkg.generated.mbti`
- `vt/cursor.mbt`
- `vt/cursor_test.mbt`
- `vt/pkg.generated.mbti`
- `examples/agent/main.mbt`
- `examples/agent/main_wbtest.mbt`
- `pkg.generated.mbti`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-tty-cursor-position.md`

## Public API Changes

- Add opaque root `Tty`.
- Add `Tty::open`, `Tty::stdio`, `Tty::close`, `Tty::read_event`,
  `Tty::with_raw_mode`, `Tty::write`, `Tty::write_string`,
  `Tty::window_size`, and `Tty::query_cursor_position`.
- Add readable root `CursorPosition { row, col }`.
- Add `@input.EventReader::read_cursor_position_response` as a terminal
  response side-channel returning row/column data, not an `Event`.
- Add `@vt.request_cursor_position`.

## Invariants

- `@input.Event` remains limited to user input and unknown input byte
  sequences.
- A CPR response consumed by the dedicated reader method must not later surface
  as a key event.
- Non-CPR bytes observed while trying to read a CPR response must remain
  available to `read_event`.
- `Tty` methods should delegate to existing `Input`/`Output` behavior and avoid
  modeling screen state.
- `examples/agent` must not enter alternate screen or clear the whole terminal
  on startup.
- `examples/agent` must reset scrolling margins, style, and cursor visibility
  on exit.

## Acceptance Criteria

- `Tty::query_cursor_position` writes `CSI 6 n` and returns a cursor position
  when the input stream provides a valid CPR response.
- `EventReader::read_cursor_position_response` parses `CSI row ; col R`,
  leaves unrelated bytes available for normal event decoding, and times out to
  `None`.
- `EventReader::read_event` no longer reports `CSI row ; col R` as an F-key.
- `examples/agent` initializes an inline viewport from cursor position when the
  terminal supports CPR, then uses scrolling margins to insert transcript above
  the composer.
- If CPR is unavailable, `examples/agent` keeps a fallback path that behaves
  like the previous primary-screen repaint demo.

## Validation Commands

```sh
moon fmt
moon test vt
moon test input
moon test .
moon test examples/agent
moon check examples/agent
moon test
moon check
moon info
```

Manual validation recommended:

```sh
moon run examples/agent
```

## Validation Results

- `moon fmt` passed.
- `moon test vt` passed: 11 tests.
- `moon test input` passed: 39 tests.
- `moon test .` passed: 15 tests.
- `moon test examples/agent` passed: 14 tests.
- `moon check examples/agent` passed.
- `moon test` passed: 93 tests.
- `moon check` passed.
- `moon info` passed and regenerated public interfaces.
- `git diff --check` passed.
- Manual PTY validation was not run in this turn.

## Public API Audit

- Root package now exposes opaque `Tty` plus readable
  `CursorPosition { row, col }`.
- `Tty` exposes only coordination/delegation methods needed for terminal
  request/response and basic terminal I/O. It does not expose screen state,
  layout, widgets, scrollback, or terminal-emulator state.
- `@input.Event` is unchanged. CPR remains outside the user-input event model.
- `@input.EventReader::read_cursor_position_response` is public because root
  `Tty` must share the same buffered reader with normal input decoding and
  cross-package private helpers are unavailable.
- `@vt.request_cursor_position` is a byte constant only; `vt` still owns no
  output stream or terminal state.
- `examples/agent` changes remain demo-local and expose no package API.
