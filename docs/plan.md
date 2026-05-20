# Execution Plan

This board tracks implementation direction for `tonyfettes/tty`. Use
`docs/plans/*.md` for task-level notes when a row becomes active.

## Legend

- `done`: implemented in previous work and kept as architectural baseline
- `active`: current work should update the linked task plan before commit
- `todo`: planned work that still needs a task plan before implementation
- `blocked`: waiting on a design decision, upstream API, or platform fact

## Board

| ID | Status | Scope | Target Files | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- |
| TTY-1 | done | stdio handles, `isatty`, `/dev/tty` open wrappers | `tty.mbt`, `isatty*.c`, `tty_unix.mbt` | Root package exposes usable `Input` and `Output` handles | `moon check`, targeted root tests |
| TTY-2 | done | termios state and raw mode | `state.mbt`, `state.c`, `cmd/raw-mode` | callers can capture, make raw, restore, and manually validate raw input | `moon check`, `moon test`, `cmd/raw-mode` manual run |
| VT-1 | done | cursor movement and visibility sequences | `vt/cursor.mbt`, `vt/cursor_test.mbt`, `cmd/cursor` | cursor helpers emit expected bytes and demo can draw a bounded region | `moon test vt`, `cmd/cursor` manual run |
| VT-2 | done | line erase and alternate screen helpers | `vt/erase.mbt`, `vt/screen.mbt`, `cmd/input`, `cmd/cursor` | demos can redraw one-line input and restore screen state | `moon test vt`, demo manual run |
| IN-1 | done | input event reader and common key sequences | `docs/plans/2026-05-20-input-event-reader.md` | `EventReader` decodes common keys while preserving unknown sequences | `moon fmt`, `moon check`, `moon test input`, `moon check cmd/input`, `moon info`, manual `cmd/input` run |
| IN-2 | done | UTF-8 text decoding via core utf8 | `docs/plans/2026-05-20-utf8-input-decoding.md`, `input/` | non-ASCII text is decoded with `moonbitlang/core/encoding/utf8` without a local utf8 package | `moon fmt`, `moon check`, `moon test input`, `moon info` |
| IN-5 | done | event reader buffer window | `docs/plans/2026-05-20-event-reader-buffer-window.md`, `input/` | `EventReader` uses one dynamic ordered byte window for current-event bytes and unread bytes | `moon fmt`, `moon check`, `moon test input`, `moon info` |
| IN-3 | done | grapheme-aware demo input buffer | `docs/plans/2026-05-20-grapheme-input-buffer.md`, `cmd/input` | demo can edit CJK and emoji text without byte-level corruption | `moon test cmd/input`, `moon test`, `moon check`, `moon info` |
| TTY-3 | done | terminal window size query | `docs/plans/2026-05-20-window-size.md`, `size.mbt`, `size.c` | output handles can query visible terminal rows and columns; non-tty outputs report `OSError` | `moon fmt`, `moon test .`, PTY `moon test .`, `moon test`, `moon check`, `moon info` |
| IN-4 | todo | bracketed paste boundary | `input/`, `vt/`, `cmd/input` | paste mode can be enabled, decoded, and bounded without unbounded memory surprises | task plan required |
| VT-3 | todo | additional ECMA-48 sequences needed by demos | `vt/` | helpers are grouped by behavior and documented with standard references | task plan required |
| MVP-1 | todo | Codex-like primary-screen demo | `cmd/` | scrollback stays in terminal primary screen and an input buffer redraws reliably | task plan required |

## Current Rules

- Do not start `IN-2` until `IN-1` has a committed public event shape.
- Keep `vt` byte-only unless a plan explicitly introduces platform-dispatched
  output operations.
- Keep `cmd/input` as a demo. Its grapheme-aware buffer validates higher-level
  editing behavior but does not create a public line-editing API.
- When a task touches `.mbti`, include public API audit notes in its plan.
- Do not add resize events until a plan defines signal/console-event ownership.
