# Bracketed Paste Boundary

## Goal

Support xterm bracketed paste mode as one input event without turning the
package into a line editor.

## Design

- Add VT byte constants for enabling and disabling bracketed paste mode
  (`CSI ? 2004 h` and `CSI ? 2004 l`).
- Add root `Tty` methods that write those sequences, including a scoped helper
  that disables bracketed paste after the supplied async body returns or raises.
- Add `Paste(String)` to `@input.InputEvent`.
- Decode `CSI 200 ~` as the start of a bracketed paste payload and read bytes
  until `CSI 201 ~`.
- Treat ESC and CSI bytes inside the payload as paste text, not as nested input
  events.
- Require paste payloads to be valid UTF-8. Invalid payloads become
  `Unknown(Bytes)`.
- Match crossterm and ultraviolet by accumulating paste payload bytes until the
  closing marker rather than adding a package-specific paste size cap.

## Target Files

- `vt/screen.mbt`
- `vt/screen_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `input/event.mbt`
- `input/decoder.mbt`
- `input/decoder_test.mbt`
- `examples/input/main.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files

## Public API Changes

- `@input.InputEvent` adds `Paste(String)`.
- `@vt` adds bracketed paste enable/disable byte constants.
- Root `Tty` adds bracketed paste enable/disable methods and a scoped helper.

## Invariants

- `EventReader` remains the only low-level byte-to-event decoder.
- Paste support does not add line-buffer, clipboard, or screen-rendering state.
- Paste decoding does not split payloads into partial paste events.
- Cursor-position reports, resize events, and normal key decoding keep their
  existing behavior.

## Acceptance

- `CSI 200 ~ hello CSI 201 ~` decodes as `Input(Paste("hello"))`.
- Paste payload bytes that look like keys or CSI sequences remain paste text.
- Invalid UTF-8 paste payloads decode as `Unknown`.
- Unclosed paste payloads decode as `Unknown` after the ESC timeout expires.
- Root command helpers emit the expected `?2004` sequences.
- `examples/input` appends paste text as one input event.

## Validation

- `moon fmt`
- `moon test input`
- `moon test vt`
- `moon test .`
- `moon check examples/input`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added `Paste(String)` to `@input.InputEvent`.
- Added bracketed paste enable/disable VT byte constants.
- Added root `Tty` methods for enabling, disabling, and scoped bracketed paste
  mode.
- Decoded `CSI 200 ~ ... CSI 201 ~` as one paste input event when the payload is
  complete and valid UTF-8.
- Kept invalid and unclosed paste sequences as `Unknown`.
- Updated `examples/input` to enable bracketed paste and append paste text as
  one event.
- Updated example event matches for the new paste input variant.

## Public API Audit

- `@input` `.mbti` adds only `InputEvent::Paste(String)`.
- Root `.mbti` adds only bracketed paste command methods on `Tty`.
- `@vt` `.mbti` adds only bracketed paste enable/disable byte constants.
- Parser helpers remain private.
- No screen renderer, line editor, clipboard API, or terminal-emulator state was
  added.

## Validation Results

- `moon fmt`
- `moon test input` -> 43 passed
- `moon test vt` -> 12 passed
- `moon test .` -> 11 passed
- `moon check examples/input`
- `moon test` -> 97 passed
- `moon check`
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
