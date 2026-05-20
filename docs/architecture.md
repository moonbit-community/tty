# Architecture

This document records stable design boundaries for `tonyfettes/tty`. It is the
place to preserve decisions that would otherwise be rediscovered in chat.

## Goals

- Provide a low-level, cross-platform terminal foundation for MoonBit programs.
- Expose enough abstraction for Unix file descriptors and Windows console
  handles without forcing callers into a full TUI framework.
- Keep terminal output sequencing, tty state, and input event decoding separated.
- Support small interactive demos that validate behavior on real terminals.

## Non-Goals

- No screen renderer or terminal emulator state in this package.
- No widget, layout, pane, scrollback, or text-field framework.
- No terminfo abstraction until a task plan identifies a concrete need.
- No platform-specific public API unless the common abstraction cannot express
  the behavior safely.

## Package Map

### Root Package

The root `tonyfettes/tty` package owns platform tty handles and stateful terminal
operations:

- stdio handles: `stdin`, `stdout`, `stderr`
- `/dev/tty` style open operations where supported
- `isatty`
- output-side terminal window size queries
- output-side command helpers for common screen, cursor, and style operations
- input state operations such as `Input::get_state`, `Input::set_state`, and raw
  mode helpers
- async read/write through the package's `Input` and `Output` wrappers

Platform FFI belongs here because raw mode, terminal dimensions, and handle
lifetime are properties of the underlying terminal device, not of VT byte
generation.

### `vt`

`tonyfettes/tty/vt` is a pure byte-sequence package.

It should:

- construct cursor movement sequences
- construct erase sequences
- construct screen mode sequences such as alternate-screen enter/leave
- construct scrolling-margin and reverse-index sequences
- construct low-level SGR sequences
- document the standard or terminal family each sequence comes from

It should not:

- write to `Output`
- depend on `@io.Writer`
- remember cursor position
- model a screen buffer

Callers decide when and where to write the returned `Bytes`.

Small CSI and SGR byte builders live inside `vt` as implementation helpers.
Only intentionally supported protocol helpers such as `sgr1`, `sgr3`, and
`sgr5` should appear in the public interface.

### `color`

`tonyfettes/tty/color` is a semantic color value package.

It should:

- define color values for terminal foreground/background commands
- represent ANSI basic/bright colors, indexed 256 colors, and truecolor RGB
- stay independent from output streams, environment variables, terminfo, and
  platform FFI

It should not:

- construct SGR byte sequences
- expose foreground/background/reset command functions
- detect terminal color capability
- decide whether colors should be enabled
- mutate terminal palettes or query terminal color state

Root `Output` methods map color values onto SGR byte sequences when writing to
an output stream. Raw byte callers should use low-level `vt` helpers directly.

Color capability detection belongs in a future higher-level package or plan
because it combines tty state, environment policy, and terminal conventions.

### `input`

`tonyfettes/tty/input` decodes host input bytes into input events.

Current shape:

- `EventReader` reads from an `@io.Reader`
- `EventReader::read_event` owns the ESC timeout boundary
- `Event` currently contains key events and unknown byte sequences
- unsupported or intentionally unmodeled sequences should become `Unknown`
  rather than hard errors

The decoder should stay focused on terminal input events. Higher-level line
editing, Unicode grapheme management, completion queues, history, and prompt
redraw belong in a caller or a future higher-level package.

`KeyEvent::text` is decoded terminal text, not a promise about grapheme
clusters, display columns, or cursor movement. Callers that edit visible text
must segment and measure that text at their own layer.

### `examples`

`examples/*` packages are manual validation tools in a separate workspace
module:

- `examples/raw` validates raw mode behavior on a real tty
- `examples/cursor` validates VT cursor/screen sequences visually
- `examples/input` validates input decoding and line-buffer experiments
- `examples/pager` validates primary-screen paging with a fixed status row and
  scrolling margins
- `examples/color` validates SGR color output visually
- `examples/agent` validates primary-screen transcript output with a trailing input
  region that starts at the current cursor location

These commands can carry small UI experiments, but public API decisions should
be recorded in `docs/architecture.md` or an active task plan before being moved
into library packages.

`examples/input` currently owns a demo-only grapheme-aware input buffer. It uses
`kawaz/grapheme` for UAX #29 grapheme clusters and `rami3l/unicodewidth` for
terminal display width. This validates Unicode editing behavior in a real
terminal while keeping `tonyfettes/tty/input` below line-editor scope.

## Cross-Platform Model

Unix platforms generally use file descriptors and termios state. Windows may
need separate console handles and API calls for operations that are VT sequences
on Unix-like terminals.

The public API should describe terminal capabilities in terms of input, output,
state, and events. The implementation can choose fd-based or handle-based
storage per target.

Window size is exposed as an output-side query because it describes the visible
screen buffer used for painting. Resize notification is deliberately separate
from size querying and should not be added without a plan for Unix signal and
Windows console-event ownership.

## Raw Mode

Raw mode is input-side terminal state. It can be exposed through `Input` because
the operation applies to the terminal device behind that input handle.

State snapshots should be explicit:

- `Input::get_state` captures current terminal state
- `State::make_raw` derives a raw-mode state from a captured state
- `Input::set_state` applies a state and returns the previous state
- scoped helpers such as `Input::with_raw_mode` should restore captured state

Nested raw-mode calls are valid only when each caller restores the state it
captured. The package should not hide raw mode behind one global singleton.

## VT Sequences

VT sequence helpers should prioritize:

- predictable byte output
- low allocation for common short sequences
- clear comments identifying ECMA-48, DEC, xterm, or Microsoft Console VT
  references when relevant

Windows API equivalents can be added later behind output operations only when a
specific operation needs platform dispatch. Pure `vt` helpers remain byte-only.

## Input Decoding

Input decoding has three boundaries:

- byte acquisition from `@io.Reader`
- ESC timeout handling
- conversion from recognized byte patterns to `Event`

The timeout boundary belongs close to byte acquisition because a standalone ESC
cannot be distinguished from the start of a longer escape sequence without
waiting. `EventReader` is the current boundary for that behavior.

Unsupported complete sequences should produce `Unknown(Bytes)`. Incomplete ESC
or CSI sequences can become `Unknown` after timeout. This keeps the public API
usable before the decoder knows every terminal sequence.

## Public API Rule

Every `.mbti` change is an API decision. Before committing a public API change,
the active plan should state:

- the external consumer story
- whether the change is breaking
- why an internal helper is not enough
- which demos or tests validate the contract
