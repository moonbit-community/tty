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
| TTY-2 | done | termios state and raw mode | `state.mbt`, `state.c`, `examples/raw` | callers can capture, make raw, restore, and manually validate raw input | `moon check`, `moon test`, `examples/raw` manual run |
| VT-1 | done | cursor movement and visibility sequences | `vt/cursor.mbt`, `vt/cursor_test.mbt`, `examples/cursor` | cursor helpers emit expected bytes and demo can draw a bounded region | `moon test vt`, `examples/cursor` manual run |
| VT-2 | done | line erase and alternate screen helpers | `vt/erase.mbt`, `vt/screen.mbt`, `examples/input`, `examples/cursor` | demos can redraw one-line input and restore screen state | `moon test vt`, demo manual run |
| IN-1 | done | input event reader and common key sequences | `docs/plans/2026-05-20-input-event-reader.md` | `EventReader` decodes common keys while preserving unknown sequences | `moon fmt`, `moon check`, `moon test input`, `moon check examples/input`, `moon info`, manual `examples/input` run |
| IN-2 | done | UTF-8 text decoding via core utf8 | `docs/plans/2026-05-20-utf8-input-decoding.md`, `input/` | non-ASCII text is decoded with `moonbitlang/core/encoding/utf8` without a local utf8 package | `moon fmt`, `moon check`, `moon test input`, `moon info` |
| IN-5 | done | event reader buffer window | `docs/plans/2026-05-20-event-reader-buffer-window.md`, `input/` | `EventReader` uses one dynamic ordered byte window for current-event bytes and unread bytes | `moon fmt`, `moon check`, `moon test input`, `moon info` |
| IN-3 | done | grapheme-aware demo input buffer | `docs/plans/2026-05-20-grapheme-input-buffer.md`, `examples/input` | demo can edit CJK and emoji text without byte-level corruption | `moon test examples/input`, `moon test`, `moon check`, `moon info` |
| TTY-3 | done | terminal window size query | `docs/plans/2026-05-20-window-size.md`, `size.mbt`, `size.c` | output handles can query visible terminal rows and columns; non-tty outputs report `OSError` | `moon fmt`, `moon test .`, PTY `moon test .`, `moon test`, `moon check`, `moon info` |
| IN-4 | todo | bracketed paste boundary | `input/`, `vt/`, `examples/input` | paste mode can be enabled, decoded, and bounded without unbounded memory surprises | task plan required |
| VT-3 | done | scroll region and reverse index sequences | `docs/plans/2026-05-20-vt-scroll-region.md`, `vt/` | demos can set/reset terminal scrolling margins and emit RI without `vt` owning output or screen state | `moon fmt`, `moon test vt`, `moon test`, `moon check`, `moon info` |
| VT-4 | done | SGR color byte sequences | `docs/plans/2026-05-20-vt-color.md`, `vt/`, `examples/color` | `vt` exposes low-level SGR builders and specimen demo shows basic, indexed, and truecolor colors | `moon fmt`, `moon test vt`, `moon check examples/color`, `moon test`, `moon check`, `moon info`, manual `examples/color` run |
| COLOR-1 | done | semantic color package and output command helpers | `docs/plans/2026-05-20-color-output-api.md`, `color/`, `vt/`, root package, `examples/color`, `examples/agent` | `color/` owns semantic color values, `vt` exposes low-level SGR builders, and `Output` has command-style style/screen helpers | `moon fmt`, `moon test vt`, `moon test color`, `moon test .`, `moon check examples/color`, `moon check examples/agent`, `moon test`, `moon check`, `moon info` |
| VT-5 | done | VT package cleanup | `docs/plans/2026-05-20-vt-package-cleanup.md`, `vt/`, `docs/architecture.md`, `docs/plan.md` | obsolete `vt/color` and `vt/internal/seq` packages are removed, while private CSI helpers and public SGR helpers live in `vt` | `moon fmt`, `moon test vt`, `moon test color`, `moon check examples/color`, `moon check examples/agent`, `moon test`, `moon check`, `moon info` |
| COLOR-2 | done | color output-only API | `docs/plans/2026-05-20-color-output-only-api.md`, `color/`, root package, `examples/color`, `examples/agent` | `color/` exposes only semantic color values; terminal color commands live on `Output`; raw byte callers use `vt.sgr*` | `moon fmt`, `moon test color`, `moon test .`, `moon check examples/color`, `moon check examples/agent`, `moon test`, `moon check`, `moon info` |
| WORKSPACE-1 | done | examples workspace split | `docs/plans/2026-05-20-examples-workspace.md`, `moon.work`, `moon.mod`, `examples/` | demos live in an `examples` module and root `moon check` covers both workspace members | `moon fmt`, `moon check`, `moon test`, `moon info`, targeted `moon check examples/*` |
| CMD-1 | done | primary-screen pager demo | `docs/plans/2026-05-20-cmd-pager.md`, `examples/pager` | demo pages a required file path with raw input, terminal size query, scroll margins, and RI | `moon fmt`, `moon test examples/pager`, `moon check examples/pager`, `moon test`, `moon check`, `moon info`, manual PTY smoke |
| MVP-1 | done | primary-screen agent demo | `docs/plans/2026-05-20-cmd-agent.md`, `examples/agent` | transcript enters primary-screen scrollback and a trailing input region redraws reliably without startup blank fill | `moon fmt`, `moon test examples/agent`, `moon check examples/agent`, `moon test`, `moon check`, `moon info`, manual PTY smoke |
| TTY-4 | done | coordinated tty handle and cursor probe | `docs/plans/2026-05-20-tty-cursor-position.md`, root package, `input/`, `vt/`, `examples/agent` | `Tty` coordinates input/output for CPR while `Event` remains user-input only; agent can use CPR plus scroll margins for Codex-like inline viewport insertion | `moon fmt`, `moon test vt`, `moon test input`, `moon test .`, `moon test examples/agent`, `moon check examples/agent`, `moon test`, `moon check`, `moon info` |
| TTY-5 | done | hide root event reader construction | `docs/plans/2026-05-20-hide-root-event-reader.md`, root package, `examples/input`, `examples/pager` | root callers read decoded terminal events through `Tty`, while `@input.EventReader` stays available only from the low-level input package | `moon fmt`, `moon test .`, `moon test input`, `moon check examples/input`, `moon check examples/pager`, `moon test`, `moon check`, `moon info` |
| TTY-6 | done | make `Tty` the root terminal capability API | `docs/plans/2026-05-20-tty-primary-api-shrink.md`, root package, examples | terminal capabilities move off public `Input`/`Output` methods and onto `Tty`; `Input`/`Output` remain low-level handles | `moon fmt`, `moon test .`, `moon check examples/raw`, `moon check examples/cursor`, `moon check examples/color`, `moon check examples/pager`, `moon test`, `moon check`, `moon info`, `git diff --check` |
| TTY-7 | done | trait-based terminal handles | `docs/plans/2026-05-20-tty-reader-writer-traits.md`, root package | `Tty::new` accepts any terminal reader/writer pair implementing root traits while `Tty` stays opaque and non-generic | `moon fmt`, `moon test .`, `moon check examples/agent`, `moon test`, `moon check`, `moon info`, `git diff --check` |

## Current Rules

- Do not start `IN-2` until `IN-1` has a committed public event shape.
- Keep `vt` byte-only unless a plan explicitly introduces platform-dispatched
  output operations.
- Keep `examples/input` as a demo. Its grapheme-aware buffer validates higher-level
  editing behavior but does not create a public line-editing API.
- When a task touches `.mbti`, include public API audit notes in its plan.
- Do not add resize events until a plan defines signal/console-event ownership.
