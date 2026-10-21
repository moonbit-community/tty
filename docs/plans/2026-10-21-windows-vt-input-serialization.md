# Windows Console Input As VT Bytes

## Goal

Serialize Windows console input records into VT input bytes and feed one byte
stream to the shared `internal/input.EventReader`, following
charmbracelet/ultraviolet (`terminal_reader_windows.go`). This replaces the
two-lane Windows backend (VT byte lane plus a direct `KeyEvent`/mouse/focus/
resize lane) from TTY-21, TTY-22, and TTY-24. Resize stays out-of-band, as on
Unix.

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

Record encoding (`internal/win32`), mirroring ultraviolet for input records:

| Record | VT bytes |
| --- | --- |
| `KEY_EVENT`, VT input enabled | key-down `UnicodeChar` only, UTF-16 surrogates joined, written as UTF-8 |
| `KEY_EVENT`, VT input disabled | `CSI Vk ; Sc ; Uc ; Kd ; Cs ; Rc _` (win32-input-mode); `Vk == 0` or surrogate `Uc` writes UTF-8 text |
| `MOUSE_EVENT` | SGR mouse `CSI < Cb ; col ; row M/m` |
| `FOCUS_EVENT` | `CSI I` / `CSI O` |
| `WINDOW_BUFFER_SIZE_EVENT` | nothing; reported out-of-band (see below) |
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

Resize (out-of-band):

- `ConsoleReader` holds a private `@aqueue.Queue[Unit]` with
  `DiscardLatest(1)`. A window buffer size record read in `_direct_read` puts a
  notification into it, coalescing repeats like a burst of `SIGWINCH`.
- `ConsoleReader::wait_resize` waits for that notification. Records are read
  only while the byte stream is read, so root `Tty::read_event` races the
  decoder against `wait_resize`, exactly as it races `SIGWINCH` on Unix.
- After a notification root `Tty` queries the visible window size. The record
  payload is the screen buffer size, which in classic conhost includes
  scrollback rows.
- A resize record consumed while a request/response query reads leaves the
  notification pending for the next `Tty::read_event`.

Decoding (`internal/input`):

- New `internal/input/win32` subpackage, parallel to `internal/input/kitty`,
  parses win32-input-mode key report parameters into `KeyEvent`. The virtual
  key table moves there from `internal/win32/key.mbt`.
- The main decoder dispatches `CSI ... _` to that subpackage and falls back to
  `Unknown` for unmappable reports.

Root package:

- One `Tty` struct definition on every platform with one `@input.EventReader`
  and a `console : @win32.ConsoleReader?` field. On a Windows console input
  handle, `console` is the decoder's byte source; everywhere else the decoder
  reads the input handle and `console` is `None`.
- Shared `Tty::read_event_from_sources` races decoded input against
  `ConsoleReader::wait_resize` when `console` is present, and otherwise calls
  the per-platform `Tty::read_byte_stream_event` (Unix: race against
  `SIGWINCH`; Windows: redirected input, no resize source, as before).
- Delete `WindowsInput`, `Tty::read_win32_console_event`,
  `Tty::read_win32_event`, both `read_internal_event_from_sources` variants,
  and `non_windows_imports.mbt`.

## Decision: Resize Stays Out-of-Band

The first revision of this plan encoded window buffer size records in-band as
xterm text area size reports (`CSI 8 ; rows ; cols t`), as ultraviolet does.
Review rejected that: resize is out-of-band on Unix (`SIGWINCH`), in-band resize
in VT terminals is the opt-in mode 2048, and the in-band encoding forced a new
internal `TextAreaSize` stream event, platform-dependent interpretation of it,
a `pending_input` to `pending_events` change so queries would not drop it, and a
Unix behavior change for stray `CSI 8 ; r ; c t` reports. Focus and mouse stay
in-band because they are terminal input sequences.

## Target Files

- `internal/input/win32/` (new): `moon.pkg`, `key.mbt`, `key_test.mbt`
- `internal/input/decoder.mbt`, `internal/input/moon.pkg`, decoder tests
- `internal/win32/`: `encoder.mbt` (new), `console_reader.mbt` (new, replaces
  `event_reader.mbt`), `win32_input.c`, `record.mbt`, `moon.pkg`; delete
  `key.mbt`, `mouse.mbt`, `event_reader.mbt`; replace
  `event_reader_wbtest.mbt` with encoder tests
- root: `tty.mbt`, `win32_input.mbt`, `resize_win32.mbt`, `resize_unix.mbt`;
  delete `non_windows_imports.mbt`
- docs: `docs/plan.md`, `docs/architecture.md`

## Public API / Interface Diff

- Root `pkg.generated.mbti`: unchanged.
- `input/pkg.generated.mbti`: unchanged.
- `internal/input/pkg.generated.mbti`: unchanged.
- `internal/input/win32/pkg.generated.mbti`: new internal package.
- `internal/win32/pkg.generated.mbti`: drops `Event`, `EventReader`,
  `MouseButtonState`, and `KeyRecord` translation methods; adds
  `ConsoleReader` with `new`, `wait_resize`, and its `@async/io.Reader` impl.

## Behavior Changes

- Keys, mouse, and focus from a Windows console are delivered in record order.
  Resize is not ordered against decoded input, on either platform.
- With VT input enabled (raw mode), key input is exactly the VT text the
  console produces, the same as on Unix terminals: for example Shift+printable
  carries no Shift modifier, and keypad digits carry no keypad state.
- With VT input disabled, key semantics follow the previous direct mapping
  (now in `internal/input/win32`).
- Repeated Windows resize records between two reads coalesce into one
  `Resize`, like `SIGWINCH`.
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
- `ConsoleReader::read_record` dispatches one record: resize records notify
  `wait_resize`, and every record goes through the encoder. It is split out of
  `fill` so tests can feed records without a console.
- `win32_input.c` gains `moonbit_tty_console_input_vt_enabled`, which reads
  `ENABLE_VIRTUAL_TERMINAL_INPUT` from the console input mode.
- `internal/input/win32.parse_key` decodes win32-input-mode reports with the
  virtual key table moved from `internal/win32/key.mbt`; the decoder dispatches
  `CSI ... _` to it.
- Root `Tty` has one struct definition and one decoder. A `#cfg`-selected
  `ConsoleRecordInput` constant gates console reader creation in
  `console_input_reader`, so shared code references `@win32.ConsoleReader` on
  every platform without unused-field or unused-parameter warnings.

## Validation Results

- Passed: `moon fmt`
- Passed: `moon check --deny-warn`
- Passed: `moon test internal/input/win32` (8 tests)
- Passed: `moon test internal/win32` (17 tests)
- Passed: `moon test --deny-warn` (203 tests)
- Passed: `moon test` in `tests/` (171 tests)
- Passed: `moon info`; root, `input`, and `internal/input` `.mbti` unchanged
- Passed: `moon check --deny-warn` on a throwaway copy with the Windows and
  non-Windows `#cfg` conditions swapped, to type-check the Windows-only root
  code on macOS
- Pending: `windows-latest` CI
- Pending: manual Windows Terminal and classic conhost validation with
  `examples/input`

## Public API Audit

- Root `pkg.generated.mbti` and `input/pkg.generated.mbti` are unchanged.
- `internal/input/win32` exports only `parse_key`, consumed by the decoder.
- `internal/win32` exports `ConsoleReader` as an opaque type with
  `ConsoleReader::new`, `ConsoleReader::wait_resize`, and its
  `@async/io.Reader` impl, consumed by root `Tty`. Nothing else is exported.

## Follow-up: Private Record Types

`InputRecord`, `KeyRecord`, `MouseRecord`, `ControlKeyState`, their
constructors and `InputRecord::parse`, and the record flag constants had stayed
`pub` from the two-lane backend, where root `Tty` mapped records itself. After
this change their only outside user was the black-box `record_test.mbt`, and
white-box tests do not justify visibility.

- All of them are now package-private, and the three `record_test.mbt` cases
  moved into `record_wbtest.mbt`.
- Making them private exposed dead code, which is removed rather than
  suppressed: the `NumLockOn`, `CapsLockOn`, and `EnhancedKey` flags (the
  encoder passes `dwControlKeyState` through unread; `internal/input/win32`
  has its own copies), the `Coord` payload of `WindowBufferSize` (resize is
  out-of-band and reads the visible size instead), and the record type carried
  by `Unsupported`. The encoder tests define the two flags they use.
- `internal/win32/pkg.generated.mbti` now lists only `ConsoleReader`.
- Validation: `moon fmt`, `moon check --deny-warn`, `moon test internal/win32`
  (17 tests), `moon test --deny-warn` (203 tests), `tests/` `moon test`
  (171 tests), `moon info`, `git diff --check`.
