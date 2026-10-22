# Windows Console Input As VT Bytes

> The sections up to "Follow-up: Private Record Types" describe the design as
> first built on the native polling backend. WASM-1 (#59) replaced that backend
> with the tty sidecar; "Follow-up: Rebuilt On The Sidecar Backend" below
> supersedes the `ConsoleReader`, console-mode FFI, and resize-queue parts.

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

## Follow-up: Rebuilt On The Sidecar Backend

WASM-1 (#59) moved terminal ownership into a sidecar process. The Windows
sidecar reads `ReadConsoleInputW`, forwards raw `INPUT_RECORD`s as `RECORD`
frames, and reports `WINDOW_BUFFER_SIZE_EVENT` out of band as `RESIZE` frames
(the root sees `@sidecar.Resized` interrupting a read). `internal/win32` lost
its FFI, and `main` still decoded records with the two-lane `EventReader`.
Merging `main` keeps the sidecar and re-applies the serialization on its
record stream.

Accepted shape:

- `internal/win32.RecordReader` replaces both `main`'s `EventReader` and this
  plan's `ConsoleReader`. It wraps the sidecar's raw record reader and is an
  `@async/io.Reader` of VT bytes: it reads one 20-byte record, encodes it with
  `RecordEncoder`, and hands out the bytes. A partially read record stays on
  the reader, so cancellation or a sidecar resize interrupting a read never
  loses record bytes.
- The console-mode FFI (`moonbit_tty_console_input_vt_enabled`,
  `win32_input.c`), the `ConsoleReader` resize queue, and `wait_resize` are
  gone. Resize is entirely the sidecar's out-of-band `RESIZE` path from
  WASM-1. `internal/win32` has no C stub and builds for wasm.
- Root `Tty` replaces `main`'s `InputDecoder` enum (`Bytes` / `Console`) with
  one `@input.EventReader`, whose byte source is the sidecar itself for
  `Bytes` input and `RecordReader(sidecar)` for `Records` input.
- `RecordEncoder` no longer takes `vt_input`. A key record with `Vk == 0` or a
  surrogate `Uc` becomes UTF-8 text; any other key record becomes a
  win32-input-mode report.

### Assumption: conhost VT translation records have `Vk == 0`

With `ENABLE_VIRTUAL_TERMINAL_INPUT` (the sidecar sets it in raw mode),
conhost translates keys into VT sequences and synthesizes one key record per
character. The per-record rule assumes those synthesized records carry
`Vk == 0` (and `Sc == 0`, `dwControlKeyState == 0`); recollection of
`TerminalInput::_SendInputSequence` and `InputBuffer::_writeString` agrees,
and VT bytes Windows Terminal sends through conpty take the same path, but it
has not been verified on Windows.

- Safe degradation: if a record still carries `Vk != 0` in VT mode, the
  win32-input-mode report decodes to the same key, with `Uc` and key-down
  state intact.
- Failure mode to watch: if conhost split a synthesized sequence such as
  `ESC [ A` (Up) into records that carry real virtual key codes, the decoder
  would see Esc, `[`, and `A` as three keys instead of Up.

### Manual Windows Validation

Run `examples/input` on classic conhost and on Windows Terminal:

- raw mode: arrow keys, Shift+Enter, Alt+F, F1 to F12, IME Chinese input,
  multi-line paste
- non-raw mode: `read_event` still reports arrow keys as `Up`/`Down`/... and
  not as text
- typing continuously across entering and leaving raw mode loses and reorders
  no keys
- resize: repeated resizes report the visible window size

### Open Question: Fallback If The Assumption Fails

If manual validation finds synthesized records with real virtual key codes,
switch to passing `vt_input = sidecar.is_raw()` into the encoder. Known
timing gap: `Sidecar::set_raw` flips its raw flag as soon as it sends the
`SET_RAW` frame, without an acknowledgement, and the Windows sidecar reads
input on a thread separate from its command thread, so records already read
but still in the pipe at a mode switch would be classified by the new mode.
Reporting the mode from the sidecar would close that window but changes the
protocol on both platforms; it is not worth it unless the gap shows up.

### Validation Results (after merging `main`)

- Passed: `moon fmt`
- Passed: `moon check --deny-warn` (native) and `moon check --target wasm
  --deny-warn`
- Passed: `moon test --deny-warn` (209 tests) and `moon test --target wasm
  --deny-warn` (204 tests)
- Passed: `moon test internal/win32` (18 tests, including `RecordReader`
  record-order and split-record tests)
- Passed: `moon test` in `tests/` (178 tests, pty runners with the sidecar)
- Passed: `moon info`; root, `input`, and `internal/input` `.mbti` match
  `main`; `internal/win32` exports only `RecordReader`
- Pending: `windows-latest` CI and the manual Windows validation above
