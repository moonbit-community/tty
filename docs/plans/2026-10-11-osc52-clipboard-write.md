# OSC 52 Clipboard Write

## Goal

Let callers set the system clipboard through the root `Tty` command surface,
both as a method and as a batched `Command` value.

## Status

Done.

## Context And Decisions

- A full-screen application that enables mouse tracking takes mouse events away
  from the terminal, so the terminal's own select-and-copy stops working. The
  application has to implement selection itself and hand the selected text to
  the terminal, and OSC 52 is the sequence for that.
- The sequence is `OSC 52 ; Pc ; Pd ST`, where `Pc` names the selection and
  `Pd` is the base64 encoding of the data.
- Write the system clipboard only: `Pc` is fixed to `c`. The X11/Wayland
  primary selection (`p`) is not exposed. If a caller needs it later, a separate
  command can be added without changing this one.
- Encode the text as UTF-8, then base64 with padding, using
  `moonbitlang/core/encoding/utf8` and `moonbitlang/core/encoding/base64`.
- Terminate with ST (`ESC \`), matching the OSC dynamic color queries already in
  `internal/vt`.
- An empty text produces an empty payload. Per xterm, a payload that is not
  valid base64 or `?` clears the selection, so `set_clipboard("")` clears the
  clipboard. No separate clear command is added.
- Do not add a clipboard read (`OSC 52 ; c ; ?`). Terminals commonly disable it
  for security, and it would need a new terminal response in the input decoder.
- Do not wrap the sequence for tmux/screen passthrough, split large payloads,
  or query support. Terminals that do not support OSC 52, that have clipboard
  access disabled, or that cap the payload size ignore or truncate the request;
  the package does not detect this.

## References Or Standards

- xterm control sequences, Operating System Commands, `OSC 52` (Manipulate
  Selection Data).
- RFC 4648 base64.

## Target Files

- `internal/vt/clipboard.mbt`
- `internal/vt/clipboard_test.mbt`
- `internal/vt/moon.pkg`
- `command.mbt`
- `style.mbt`
- `tty_test.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Public API Changes

Root package additions:

- `Tty::set_clipboard(Self, StringView) -> Unit`
- `Command::SetClipboard(StringView)`

Internal VT package additions:

- `set_clipboard(StringView) -> Bytes`
- `write_set_clipboard(@buffer.Buffer, StringView) -> Unit`

Internal VT package imports `moonbitlang/core/encoding/base64` and
`moonbitlang/core/encoding/utf8`.

No new public type, parser state, input event, platform backend, or capability
query is proposed.

## Invariants

- `Tty` remains the public output-command surface.
- `internal/vt` remains byte-sequence-only and does not own output streams.
- The package never reads the clipboard and adds no clipboard state.
- The input decoder is unchanged.

## Acceptance Criteria

- Internal VT helpers emit `ESC ] 52 ; c ; <base64 of UTF-8 text> ESC \`,
  including for non-ASCII text and for empty text.
- The root method and `Tty::execute` write the same bytes through `Tty`.
- Generated `.mbti` diffs contain only the intended API additions.

## Validation Commands

- `moon fmt` passed; `moon fmt --check` passed.
- `moon check --deny-warn` passed.
- `moon test internal/vt` passed: 29 tests.
- `moon test .` passed: 29 tests.
- `moon test --deny-warn` passed.
- `moon info` passed and regenerated intended `.mbti` entries.
- `git diff --check` passed.

Validation ran on macOS only. The tests assert the emitted bytes through a
pipe-backed `Tty`; they do not show that a terminal accepts the sequence. Manual
terminal validation was not done in this task. To check a terminal by hand:

```sh
printf '\033]52;c;%s\033\\' "$(printf 'hello from tty' | base64)"
```

then paste; a supporting terminal pastes `hello from tty`.

## Public API Audit

- Root `Tty` now exposes `set_clipboard` for applications that implement their
  own text selection.
- Root `Command` gains `SetClipboard` so the same operation can join a
  `Tty::execute` batch. `Command` is `pub(all)`, so the new variant breaks
  downstream code that matches it exhaustively. `Command` is intended to be
  constructed by callers rather than matched.
- Internal VT exposes `set_clipboard` and `write_set_clipboard` for the root
  command methods.
- No public parser state, platform handle, input event, wrapper type, mutable
  field, or terminal state model was added.
- The generated `.mbti` diff was reviewed and contains only the intended root
  and internal VT additions.

## Result Notes

- Added the OSC 52 sequence builder in a new `internal/vt/clipboard.mbt`, the
  root write-through method, and the `Command` variant.
- Added internal VT tests for ASCII, non-ASCII, and empty text, and a root
  pipe-backed test covering both the method and a `Tty::execute` batch.
- Updated README, architecture notes, and the execution board.

## Open Questions

- None.
