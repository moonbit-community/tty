# Windows Console Input Polling

## Goal

Deliver Windows resize events through `Tty::read_event` by reading console
input records directly, without depending on `ReadFile` or async runtime
internals.

## Accepted Design

- Use a Windows-only polling backend for root `Tty::read_event`.
- Poll the console input buffer with nonblocking C FFI wrappers around
  `PeekConsoleInputW` / `ReadConsoleInputW`.
- If no record is pending, sleep briefly with `@async.sleep(10)` so the MoonBit
  async scheduler can run other tasks.
- Convert `WINDOW_BUFFER_SIZE_EVENT` into the existing root
  `Event::Resize(WindowSize)`.
- Convert supported `KEY_EVENT_RECORD` values into existing
  `@input.InputEvent::Key` values.
- Convert `FOCUS_EVENT_RECORD` into existing `FocusIn` / `FocusOut` input
  events.
- Ignore unsupported record types after consuming them so they do not stall the
  input loop.
- Keep the existing Unix `SIGWINCH` resize backend unchanged.
- Enable `ENABLE_WINDOW_INPUT` in Windows raw mode so resize records are
  delivered to the console input buffer.

## Target Files And Surfaces

- `resize_win32.mbt`: replace the Windows byte-reader event source with the
  polling console-input backend.
- `win32_input.mbt`: private Windows record polling and record-to-event mapping.
- `win32_input.c`: Windows-only C FFI wrapper for compact console input records.
- `state.c`: raw-mode input flags gain `ENABLE_WINDOW_INPUT`.
- `moon.pkg`: include the new native stub.
- `docs/plan.md`: mark this task as active while implementation is in progress.

## API / Interface Diff

- No intended public API change.
- `pkg.generated.mbti` should remain unchanged.
- `input/pkg.generated.mbti` should remain unchanged.
- New C FFI symbols and MoonBit helpers remain private to the root package.
- `Tty` remains opaque; any Windows polling state is not exposed.

## Why Existing Code Cannot Be Reused As-Is

- `@input.EventReader` decodes terminal bytes from an `@io.Reader`; Windows
  resize notifications are `WINDOW_BUFFER_SIZE_EVENT` input records, not VT
  input bytes.
- `ReadFile` / `ReadConsole` are high-level console input APIs. They return a
  character stream and filter non-character records such as window, focus, and
  mouse events.
- `moonbitlang/async` has an internal worker pool for blocking Windows calls,
  but it does not expose a public custom-job API for `ReadConsoleInputW`, and
  `ReadConsoleInputW` is not an overlapped IOCP operation.

## Open Questions

- Windows manual validation must confirm exact key-repeat and modifier behavior
  under Windows Terminal and classic conhost.
- Mouse record mapping can be broadened later if direct console record handling
  proves preferable to VT mouse bytes on Windows.

## Next Implementation Step

Add the private Windows FFI wrapper and polling event source, then wire
`resize_win32.mbt` through that backend.

## Validation Plan

- `moon fmt`
- `moon check`
- `moon test .`
- `moon test input`
- `moon test`
- `moon info`
- Review generated `.mbti` diffs.
- `git diff --check`
- Manual Windows Terminal validation with `examples/input` resizing the window.

## Result

- Added a Windows-only console input polling backend for `Tty::read_event`.
- Added `win32_input.c` to peek and consume one console `INPUT_RECORD` without
  blocking when the input buffer is empty.
- Added `win32_input.mbt` to map key, focus, and window-size records into the
  existing root event model.
- Windows `resize_win32.mbt` now dispatches through the polling backend.
- Windows raw mode now enables `ENABLE_WINDOW_INPUT`.
- Non-console Windows input handles fall back to the existing byte decoder.

## Follow-up: Local Surrogate State

The initial implementation stored a Windows-only UTF-16 surrogate buffer on
`Tty`, which required suppressing the non-Windows `unused_field` warning because
MoonBit does not support `#cfg` on individual struct fields. The accepted
follow-up design keeps that surrogate buffer local to
`Tty::read_win32_console_event` instead. The polling loop already waits through
high-surrogate records until a complete key event is available, so this keeps
the state at the narrowest call site and removes the warning suppression.

## Follow-up: Preserve VT Byte Decoding

Automated review found that direct `KEY_EVENT_RECORD` to `KeyEvent` mapping
bypasses the existing VT byte decoder on Windows console input handles. That
breaks higher-level terminal input modes such as bracketed paste and mouse
tracking, whose reports arrive as ESC/CSI byte sequences.

Accepted implementation shape:

- Add a private `Win32ConsoleInputSource`.
- Use `@io.pipe()` for key bytes:
  - `PipeRead` is passed to a private `@input.EventReader` owned by the
    Windows console source.
  - `PipeWrite` receives key-record Unicode text as bytes for the decoder.
- Use `@aqueue.Queue[Event]` for non-byte root events such as resize and focus.
- `Tty::read_event` on Windows console handles races the existing decoder
  against the queued root events, matching Unix resize behavior.
- Keep `ReadConsoleInputW` as the single console input record consumer.
- Keep non-console Windows handles on the original byte-reader decoder.
- Keep the public API unchanged and review `.mbti` output after `moon info`.

Follow-up result:

- `Win32ConsoleInputSource` now owns the Windows console input record stream.
- Text-bearing key records are written into a private `@io.pipe()` and decoded
  by a private `@input.EventReader`, so VT sequences such as bracketed paste and
  mouse reports go through the existing byte decoder.
- Resize and focus records are queued as root `Event` values with
  `@aqueue.Queue[Event]`.
- Non-text Windows key records still map directly to `KeyEvent`, and coalesced
  repeats enqueue one event/write per repeat.
- Added a Windows white-box regression test that feeds bracketed paste key
  records through the source and expects a single decoded `Paste` event.

## Follow-up: Preserve Printable Key Modifiers

Automated review of the VT-decoding follow-up found that routing every
text-bearing Windows key record through the byte decoder loses
`control_key_state` metadata for printable modified keys such as `Alt+A` and
`Shift+Alt+X`.

Accepted implementation shape:

- Keep unmodified text key records on the private pipe so terminal-generated VT
  byte streams still go through the existing decoder.
- Route text key records with Windows keyboard modifiers through direct
  `KeyEvent` construction so `win32_modifiers()` is preserved.
- Keep resize/focus records on the `@aqueue.Queue[Event]` path.
- Keep the public API unchanged and review `.mbti` output after `moon info`.

Follow-up result:

- Added a private modifier predicate for Windows key records.
- `Win32ConsoleInputSource::read_key_record` now sends modified printable keys
  to the direct key-event path and only sends unmodified text to the decoder.
- Added a Windows white-box regression test for `Alt+a` and `Shift+Alt+X`
  printable key records.

## Follow-up: Preserve Keypad Metadata

Automated review of the printable-key follow-up found that unmodified numpad
records also carry printable Unicode text while relying on virtual-key and lock
state metadata to distinguish keypad keys from ordinary text.

Accepted implementation shape:

- Keep unmodified non-keypad text key records on the private pipe so
  terminal-generated VT byte streams still go through the existing decoder.
- Route keypad virtual-key records through direct `KeyEvent` construction so
  `Keypad*`, `keypad`, and `num_lock` state are preserved.
- Keep the public API unchanged and review `.mbti` output after `moon info`.

Follow-up result:

- Added a private direct-metadata predicate for Windows key records.
- `Win32InputRecord::win32_key_text_uses_decoder` now excludes both keyboard
  modifiers and keypad virtual keys from the byte-decoder path.
- Added a Windows white-box regression test for `VK_NUMPAD1` and
  `VK_MULTIPLY` records carrying printable Unicode text.

## Follow-up: Preserve Keypad Enter Metadata

Automated review of the keypad follow-up found that numeric-keypad Enter is
reported as `VK_RETURN` with the Windows `ENHANCED_KEY` bit, rather than as one
of the numeric keypad virtual keys.

Accepted implementation shape:

- Treat `VK_RETURN` with `ENHANCED_KEY` as keypad metadata.
- Decode that record as `KeypadEnter` and mark the key state as `keypad`.
- Keep ordinary `VK_RETURN` behavior unchanged.
- Keep the public API unchanged and review `.mbti` output after `moon info`.

Follow-up result:

- Added the private Windows `ENHANCED_KEY` bit constant.
- Added private record-level helpers for keypad detection and virtual-key code
  mapping.
- Added a Windows white-box regression test for keypad Enter.

## Follow-up: Preserve AltGr Text Input

Automated review of the printable-key modifier follow-up found that Windows
keyboard layouts using AltGr report printable text records with
`RIGHT_ALT_PRESSED | LEFT_CTRL_PRESSED`, which the modifier predicate can
misclassify as an explicit `Ctrl+Alt` shortcut chord.

Accepted implementation shape:

- Treat printable key records with the Windows AltGr state as text input for the
  private byte decoder.
- Keep explicit modified printable keys such as `Alt+a` and `Shift+Alt+X` on
  the direct `KeyEvent` path so their modifier metadata is preserved.
- Keep keypad virtual-key records and keypad Enter on the direct `KeyEvent`
  path.
- Keep the public API unchanged and review `.mbti` output after `moon info`.

Follow-up result:

- Added a private Windows AltGr text predicate used only by the key-record
  decoder/direct-event routing decision.
- `Win32InputRecord::win32_key_text_uses_decoder` now keeps printable
  `RIGHT_ALT_PRESSED | LEFT_CTRL_PRESSED` AltGr text on the byte-decoder path.
- Added a Windows white-box regression test for AltGr text input.

## Public API Audit

- No public MoonBit API changed.
- `pkg.generated.mbti` did not change after `moon info`.
- `input/pkg.generated.mbti` did not change after `moon info`.
- Windows FFI symbols, console input source state, and record mapping helpers
  remain private to the root package.

## Validation Results

- `moon fmt`: passed.
- `moon check`: passed with the pre-existing `async/raw_fd` unused-package
  warnings.
- `moon -C tests test --filter "resize event"`: passed, 1 test.
- `moon -C tests test --filter "isatty"`: passed, 2 tests.
- `moon test . --filter "win32 console source decodes bracketed paste key records"`:
  passed, 1 test.
- `moon test . --filter "win32 console source preserves printable key modifiers"`:
  passed, 1 test.
- `moon test . --filter "win32 console source preserves AltGr text input"`:
  passed, 1 test.
- `moon test . --filter "win32 console source preserves keypad key metadata"`:
  passed, 1 test.
- `moon test . --filter "win32 console source preserves keypad enter metadata"`:
  passed, 1 test.
- `moon test`: passed, 154 tests.
- `moon check --target all`: passed with the same pre-existing warnings.
- `moon info`: passed with the known Windows-generated `pkg.generated.mbti`
  `Fd::fd` drift; the generated drift was restored.
- `.mbti` review: no public interface diff remains in the worktree.
- `git diff --check`: passed.
- Windows Terminal manual resize smoke: not run in this environment.
