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

## Public API Audit

- No public MoonBit API changed.
- `pkg.generated.mbti` did not change after `moon info`.
- `input/pkg.generated.mbti` did not change after `moon info`.
- Windows FFI symbols and record mapping helpers remain private to the root
  package.

## Validation Results

- `moon fmt`: passed.
- `moon check`: passed with pre-existing `try?` deprecation warnings in
  `tty_wbtest.mbt`.
- `moon check --target all`: passed with the same pre-existing warnings.
- Temporary Windows backend typecheck: passed by copying the repo to
  `/private/tmp`, removing only `#cfg(platform="windows")` from
  `win32_input.mbt`, and running `moon check`.
- `moon test .`: passed, 25 tests.
- `moon test input`: no test entry in that package.
- `moon test internal/input`: passed, 60 tests.
- `moon test`: passed, 147 tests.
- `moon info`: passed.
- `.mbti` review: no public interface diff.
- `git diff --check`: passed.
- Windows Terminal manual resize smoke: not run in this environment.
