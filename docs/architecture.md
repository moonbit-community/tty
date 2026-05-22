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

- `Tty`, a narrow handle that coordinates one terminal input stream and output
  stream for terminal capabilities and request/response protocols
- `Tty::stdio` and `Tty::open` convenience constructors for process stdio and
  `/dev/tty` style handles where supported
- `Reader` and `Writer`, terminal-handle traits that extend async I/O with
  descriptor and close operations for `Tty::new`
  (`moonbitlang/async` files, stdio handles, and OS pipes implement them)
- `isatty`
- terminal window size queries through `Tty`
- decoded root terminal events through `Tty`
- coordinated cursor position report queries through `Tty`
- command helpers for common screen, cursor, color, and style operations
  through `Tty`
- bracketed paste mode helpers through `Tty`
- terminal state operations such as `Tty::get_state`, `Tty::set_state`, and raw
  mode helpers through `Tty`

Platform FFI belongs here because raw mode, terminal dimensions, and handle
lifetime are properties of the underlying terminal device, not of VT byte
generation.

`Tty` is intentionally opaque and non-generic. `Tty::new` accepts concrete
handles through root `Reader`/`Writer` trait bounds and stores trait objects
internally so public `Tty` methods do not carry concrete input/output types.
`Tty::stdio` and `Tty::open` are convenience constructors over those traits.
Raw file and stdio I/O belongs to `moonbitlang/async/fs` and
`moonbitlang/async/stdio`; the root package should not duplicate those APIs with
thin wrapper types.

### Internal VT Helpers

`tonyfettes/tty/internal/vt` is a pure byte-sequence implementation package used
by the root `Tty` command methods. It is not downstream API.

It should:

- construct cursor movement sequences
- construct erase sequences
- construct screen mode sequences such as alternate-screen enter/leave
- construct bracketed paste enable/disable sequences
- construct scrolling-margin and reverse-index sequences
- construct low-level SGR sequences and fixed SGR attribute bytes
- document the standard or terminal family each sequence comes from

It should not:

- be imported by examples or downstream callers
- write to or own an output stream
- depend on `@io.Writer`
- remember cursor position
- model a screen buffer

Root `Tty` methods are the public output-command surface. Small CSI and SGR byte
builders stay inside `internal/vt` as implementation helpers.

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

Root `Tty` methods map color values onto SGR byte sequences when writing to a
terminal.

Root callers that want decoded terminal events should use `Tty::read_event` so
terminal request/response side channels, resize notifications, and normal input
decoding share one coordinated handle. Direct `EventReader` construction belongs
to the low-level `input` package for callers decoding an arbitrary `@io.Reader`.

Color capability detection belongs in a future higher-level package or plan
because it combines tty state, environment policy, and terminal conventions.

### `input`

`tonyfettes/tty/input` decodes host input bytes into terminal stream events.

Current shape:

- `EventReader` reads from an `@io.Reader`
- `EventReader::read_event` owns the ESC timeout boundary and returns terminal
  stream events
- `Event` contains `Input(InputEvent)` for user input and terminal responses
  such as cursor-position reports
- `InputEvent` contains key events, complete valid UTF-8 bracketed paste
  payloads, and unknown byte sequences
- unsupported or intentionally unmodeled sequences should become `Unknown`
  input events rather than hard errors

The decoder should stay focused on terminal input events. Higher-level line
editing, Unicode grapheme management, completion queues, history, and prompt
redraw belong in a caller or a future higher-level package.

`KeyEvent::text` is decoded terminal text, not a promise about grapheme
clusters, display columns, or cursor movement. Callers that edit visible text
must segment and measure that text at their own layer.

Bracketed paste decoding treats payload bytes as text until the closing
`CSI 201 ~` marker. Payloads that are invalid UTF-8 or unclosed are reported as
`Unknown` rather than partial paste text.

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
  region that starts at the current cursor location, probes cursor position when
  available, and uses scrolling margins to keep finalized transcript insertion
  above the composer

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

The public API should describe terminal capabilities in terms of coordinated
terminal handles, state, and events. The implementation can choose fd-based or
handle-based storage per target.

Window size is exposed through `Tty` because callers usually need the visible
screen buffer size while coordinating terminal input and output. The current
query implementation uses the output-side handle. Unix resize notification is a
process-global `SIGWINCH` source surfaced as coalesced root `Tty::read_event`
resize events. Windows resize events need a later console-input backend.

## Raw Mode

Raw mode is input-side terminal state, but root callers should access it through
`Tty` so terminal capabilities share one user-facing handle. The implementation
still applies raw mode to the input side behind `Tty`.

State snapshots should be explicit:

- `Tty::get_state` captures current terminal state
- `State::make_raw` derives a raw-mode state from a captured state
- `Tty::set_state` applies a state and returns the previous state
- scoped helpers such as `Tty::with_raw_mode` should restore captured state

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
waiting. `EventReader` is the current boundary for that behavior inside the
low-level `input` package. Root terminal callers should go through
`Tty::read_event`.

Unsupported complete input sequences should produce `Input(Unknown(Bytes))`.
Incomplete ESC or CSI sequences can become `Input(Unknown(...))` after timeout.
This keeps the public API usable before the decoder knows every terminal
sequence.

Terminal request/response reports such as Cursor Position Report (`CSI row ;
col R`) are not user input events. They may appear as low-level stream events,
but root `Tty::read_event` should not surface CPR as a public root event. Root
request/response operations such as `Tty::query_cursor_position` should use the
shared reader, consume the matching response, and preserve interleaved input
events for later `Tty::read_event` calls.

## Public API Rule

Every `.mbti` change is an API decision. Before committing a public API change,
the active plan should state:

- the external consumer story
- whether the change is breaking
- why an internal helper is not enough
- which demos or tests validate the contract
