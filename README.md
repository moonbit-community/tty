# moonbit-community/tty

Low-level terminal primitives for MoonBit.

`moonbit-community/tty` provides a small foundation for programs that need to talk to a
real terminal: tty detection, raw mode, terminal size queries, output
commands, color values, and host input decoding. It is intentionally below a
full TUI framework. It does not own a screen model, layout engine, widget tree,
pane system, or scrollback buffer.

## Status

This module is early and native-target focused. Public APIs are still being
shaped around small terminal programs and the examples in this repository.

## Packages

### `moonbit-community/tty`

The root package owns coordinated terminal handles and stateful terminal
operations.

Use `Tty` when an operation needs a real terminal handle:

- process stdio: `Tty::stdio()`
- controlling terminal: `Tty::open()`
- custom handles: `Tty::new(input, output)` with `Reader` and `Writer` traits
  for async files, stdio, and OS pipes
- raw mode: `Tty::get_state`, `State::make_raw`, `Tty::set_state`,
  `Tty::with_raw_mode`
- terminal size: `Tty::window_size`
- cursor position report: `Tty::query_cursor_position`
- terminal events: `Tty::read_event`
- output commands: cursor movement/visibility, line erase, scroll margins,
  reverse index, alternate screen, bracketed paste mode,
  foreground/background colors, text attributes, and style reset

Raw file and stdio byte I/O should use `moonbitlang/async/fs` and
`moonbitlang/async/stdio` directly. The root package does not wrap them as
`stdin`, `stdout`, or `stderr`.

VT/ANSI byte construction is an internal implementation detail. Downstream callers
should use root `Tty` output command methods instead of importing byte-sequence
helpers directly.

### `moonbit-community/tty/input`

Terminal input byte decoding.

`EventReader` decodes an `@io.Reader` into terminal stream events. Stream
events wrap user input events and terminal responses such as cursor position
reports. Root callers that are working with a terminal should normally use
`Tty::read_event` so input, resize notifications, and terminal
request/response traffic share the same coordinated terminal handle.
When bracketed paste mode is enabled, complete valid UTF-8 paste payloads are
reported as one paste input event.

### `moonbit-community/tty/color`

Semantic terminal color values.

The package represents default, ANSI basic/bright, indexed 256-color, and RGB
truecolor values. Root `Tty` methods turn these values into SGR output.

## Usage

Add the module and import the packages you need in `moon.pkg`:

```moonbit
import {
  "moonbit-community/tty"
  "moonbit-community/tty/color" @tty/color
  "moonbit-community/tty/input" @tty/input
}
```

Write terminal commands through a `Tty`:

```moonbit
async fn main {
  let tty = @tty.Tty::stdio()
  tty.hide_cursor()
  tty.set_cursor_position(1, 1)
  tty.bold()
  tty.set_foreground(@tty/color.Basic(@tty/color.Green))
  tty.write("hello from tty\r\n")
  tty.reset_style()
  tty.show_cursor()
}
```

Run a scoped raw-mode input loop:

```moonbit
async fn main {
  let tty = @tty.Tty::stdio()
  tty.with_raw_mode(() => {
    tty.write("press q to quit\r\n")
    while true {
      match tty.read_event() {
        @tty.Input(@tty/input.Key(key)) =>
          match key.code {
            Char('q') => break
            _ => ()
          }
        @tty.Input(@tty/input.Paste(_)) => ()
        @tty.Input(@tty/input.Unknown(_)) => ()
        @tty.Resize(_) => ()
      }
    }
  })
}
```

## Examples

Examples live in a separate workspace member under `examples/`.

```sh
moon run examples/raw
moon run examples/input
moon run examples/color
moon run examples/cursor
moon run examples/pager -- README.md
moon run examples/agent
```

The examples are manual validation tools, not framework APIs:

- `examples/raw` checks raw mode behavior.
- `examples/input` exercises decoded key input and grapheme-aware demo editing.
- `examples/color` prints a color specimen.
- `examples/cursor` draws with cursor movement and erase sequences.
- `examples/pager` demonstrates primary-screen paging with a fixed status row.
- `examples/agent` demonstrates a Codex-like primary-screen transcript, input
  composer, delayed queued input, and shell command execution.

## Design Boundaries

- `tty` owns terminal handles, platform state, raw mode, terminal size, cursor
  position queries, and command-style terminal operations.
- internal VT helpers only build byte sequences for root `Tty` methods.
- `input` decodes host input bytes into events.
- `color` only represents semantic color values.
- Higher-level editing, layout, widgets, screen rendering, and terminal-emulator
  state belong outside this module unless the project plan changes.

See `docs/architecture.md` and `docs/plan.md` for the current design notes and
execution board.

## Development

Common validation commands:

```sh
moon fmt
moon test .
moon test
moon check
moon info
```

Review `pkg.generated.mbti` after `moon info`; it is the public API surface.
