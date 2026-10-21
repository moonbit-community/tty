# Windows Console Input As VT Bytes

## Goal

Serialize every Windows console `INPUT_RECORD` into VT input bytes and feed
one byte stream to the shared `internal/input.EventReader`, following
charmbracelet/ultraviolet (`terminal_reader_windows.go`). This replaces the
two-lane Windows backend (VT byte lane plus a direct `KeyEvent`/mouse/focus/
resize lane) from TTY-21, TTY-22, and TTY-24.

## Problem

- The direct lane and the byte lane have no total order, which
  `docs/architecture.md` documents as a known gap.
- Key translation exists twice (`internal/win32/key.mbt` and the byte decoder);
  TTY-21 follow-ups (Ctrl+[, Ctrl+Space, printable modifiers, split VT tails
  under cancellation) are all symptoms of the split.
- Each `read_event` spawns a short-lived record producer, and root `Tty`
  carries a Windows-only struct definition, `WindowsInput` backend enum, and
  per-platform `read_internal_event_from_sources`.

## Accepted Design

Record encoding (`internal/win32`), mirroring ultraviolet:

| Record | VT bytes |
| --- | --- |
| `KEY_EVENT`, VT input enabled | key-down `UnicodeChar` only, UTF-16 surrogates joined, written as UTF-8 |
| `KEY_EVENT`, VT input disabled | `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _` (win32-input-mode); `Vk == 0` or surrogate `Uc` writes UTF-8 text |
| `MOUSE_EVENT` | SGR mouse `CSI < Cb ; col ; row M/m` |
| `WINDOW_BUFFER_SIZE_EVENT` | xterm text area size report `CSI 8 ; rows ; cols t` |
| `FOCUS_EVENT` | `CSI I` / `CSI O` |
| other | nothing |

- Key-up records are dropped, and lone modifier key-downs (Shift, Ctrl, Alt,
  Win, CapsLock with `Uc == 0`) are dropped, matching the previous backend and
  non-kitty terminals.
- `repeat_count` is expanded into that many copies of the encoded key.
- Whether VT input is enabled is read from the console input mode once per
  drained batch, because `Tty::set_state` can toggle raw mode at any time.
- The win32-input-mode encoding is produced locally from `ReadConsoleInputW`
  records. The package never enables private mode 9001 on the terminal.

Reading (`internal/win32.ConsoleReader`):

- Implements `@async/io.Reader`. `_direct_read` returns pending encoded bytes
  when available; otherwise it synchronously drains available records with the
  existing non-blocking peek/read FFI and encodes them; when nothing was
  available it sleeps 10ms and retries.
- The only async suspension point is the sleep, so ESC-timeout cancellation in
  the decoder cannot drop records that were already read from the console.
- No background producer task and no direct-event queue.

Decoding (`internal/input`):

- New `internal/input/win32` subpackage, parallel to `internal/input/kitty`,
  parses win32-input-mode key report parameters into `KeyEvent`. The virtual
  key table moves there from `internal/win32/key.mbt`.
- The main decoder dispatches `CSI ... _` to that subpackage and falls back to
  `Unknown` for unmappable reports.
- New internal stream event `TextAreaSize(rows~, cols~)` for `CSI 8 ; r ; c t`.
  It is a terminal report, not user input.

Root package:

- One `Tty` struct definition on every platform with one `@input.EventReader`.
  On Windows console input handles, the reader's source is a
  `@win32.ConsoleReader`; everywhere else it is the input handle itself.
- Delete `WindowsInput`, `Tty::read_win32_console_event`,
  `Tty::read_win32_event`, and both `read_internal_event_from_sources`
  variants.
- On Windows, `TextAreaSize` maps to `Resize(window_size())`. The record
  payload is the screen buffer size, which in classic conhost includes
  scrollback rows, so the visible size is queried again. On Unix the report is
  ignored like other terminal responses.
- `pending_input : Array[InputEvent]` becomes `pending_events : Array[Event]`
  so a Windows resize that arrives while a request/response query is waiting is
  preserved for the next `Tty::read_event` instead of being dropped. (Deviation
  noted during implementation: a direct consequence of moving resize into the
  byte stream.)

## Target Files

- `internal/input/win32/` (new): `moon.pkg`, `key.mbt`, `key_test.mbt`
- `internal/input/decoder.mbt`, `internal/input/event.mbt`,
  `internal/input/moon.pkg`, decoder tests
- `internal/win32/`: `encoder.mbt` (new), `console_reader.mbt` (new, replaces
  `event_reader.mbt`), `win32_input.c`, `record.mbt`; delete `key.mbt`,
  `mouse.mbt`, `event_reader.mbt`; replace `event_reader_wbtest.mbt` with
  encoder tests
- root: `tty.mbt`, `win32_input.mbt`, `resize_win32.mbt`,
  `non_windows_imports.mbt`
- docs: `docs/plan.md`, `docs/architecture.md`

## Public API / Interface Diff

- Root `pkg.generated.mbti`: unchanged.
- `input/pkg.generated.mbti`: unchanged.
- `internal/input/pkg.generated.mbti`: adds `Event::TextAreaSize`.
- `internal/input/win32/pkg.generated.mbti`: new internal package.
- `internal/win32/pkg.generated.mbti`: drops `Event`, `EventReader`,
  `MouseButtonState`, and `KeyRecord` translation methods; adds
  `ConsoleReader` with its `@async/io.Reader` impl.

## Behavior Changes

- Keys, mouse, focus, and resize from a Windows console are delivered in record
  order.
- With VT input enabled (raw mode), key input is exactly the VT text the
  console produces, the same as on Unix terminals: for example Shift+printable
  carries no Shift modifier, and keypad digits carry no keypad state.
- With VT input disabled, key semantics follow the previous direct mapping
  (now in `internal/input/win32`).
- Focus records are still reported unconditionally and mouse records are not
  filtered by a mouse mode, as before.

## Validation Plan

- `moon fmt`
- `moon check`
- `moon test internal/input/win32`
- `moon test internal/input`
- `moon test internal/win32`
- `moon test .`
- `moon test`
- `moon info`, review `.mbti` diffs
- `git diff --check`
- Windows-only root code is type-checked by the `windows-latest` CI job.
- Manual: `examples/input` on Windows Terminal and classic conhost (keys,
  modifiers, paste, mouse, focus, resize), raw and non-raw.

## Result

- `internal/win32` now encodes records with a private `RecordEncoder` and
  reads them through `ConsoleReader` (`@async/io.Reader`). The old `Event`,
  `EventReader`, key translation, and mouse translation are removed; the
  package no longer depends on `internal/input` or `tty/input`.
- `win32_input.c` gains `moonbit_tty_console_input_vt_enabled`, which reads
  `ENABLE_VIRTUAL_TERMINAL_INPUT` from the console input mode.
- `internal/input/win32.parse_key` decodes win32-input-mode reports with the
  virtual key table moved from `internal/win32/key.mbt`; the decoder dispatches
  `CSI ... _` to it and decodes `CSI 8 ; rows ; cols t` as `TextAreaSize`.
- Root `Tty` has one struct definition and one decoder. A `#cfg`-selected
  `ConsoleRecordInput` constant gates the Windows-only branches in
  `input_byte_source` and `Tty::text_area_size_event`, so the shared code
  references `@win32.ConsoleReader` on every platform and
  `non_windows_imports.mbt` is no longer needed.
- Request/response queries defer any root event they read through
  `Tty::defer_event` into `pending_events`.
- On Unix a stray `CSI 8 ; rows ; cols t` is now treated as a terminal response
  and dropped; it previously surfaced as `Input(Unknown(...))`.

## Validation Results

- Passed: `moon fmt`
- Passed: `moon check --deny-warn`
- Passed: `moon test internal/input/win32` (8 tests)
- Passed: `moon test internal/input` (66 tests)
- Passed: `moon test internal/win32` (16 tests)
- Passed: `moon test --deny-warn` (203 tests)
- Passed: `moon test` in `tests/` (171 tests)
- Passed: `moon info`; root and `input` `.mbti` unchanged
- Passed: `moon check --deny-warn` on a throwaway copy with the Windows and
  non-Windows `#cfg` conditions swapped, to type-check the Windows-only root
  code on macOS
- Pending: `windows-latest` CI
- Pending: manual Windows Terminal and classic conhost validation with
  `examples/input`

## Public API Audit

- Root `pkg.generated.mbti` and `input/pkg.generated.mbti` are unchanged.
- `internal/input` adds `Event::TextAreaSize(rows~, cols~)`, needed for the
  root package to see Windows resize reports from the byte stream.
- `internal/input/win32` exports only `parse_key`, consumed by the decoder.
- `internal/win32` exports `ConsoleReader` as an opaque type with
  `ConsoleReader::new` and its `@async/io.Reader` impl, consumed by root `Tty`.
  `RecordEncoder` is `priv`. The existing record types and flag constants stay
  exported for the black-box record tests.
