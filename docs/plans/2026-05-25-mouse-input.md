# Mouse Input

## Goal

Support cell-coordinate SGR mouse input as low-level terminal input events,
without adding a screen model, widget layer, or terminal-emulator state.

## Design

- Add `Mouse` input events to `moonbit-community/tty/input`.
- Decode xterm SGR mouse reports only: `CSI < cb ; col ; row M/m`.
- Keep coordinates 1-based terminal cell coordinates, matching existing cursor
  command and cursor-position APIs.
- Add root `Tty` helpers that enable and disable SGR mouse reporting:
  - `Click` maps to `?1000h` plus `?1006h`.
  - `Drag` maps to `?1002h` plus `?1006h`.
  - `Motion` maps to `?1003h` plus `?1006h`.
- Keep 1016 SGR-pixel, X10, UTF-8 mouse, and urxvt mouse out of the MVP.
- Treat malformed reports, zero coordinates, and unsupported buttons as
  `Unknown(Bytes)`.

## Target Files

- `input/event.mbt`
- `internal/input/decoder.mbt`
- `internal/input/decoder_test.mbt`
- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `examples/input/main.mbt`
- `examples/input/main_wbtest.mbt`
- `examples/pager/main.mbt`
- `examples/agent/main.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files

## Public API Changes

- `@input.InputEvent` adds `Mouse(MouseEvent)`.
- `@input` adds public readable mouse event data types:
  - `MouseEvent`
  - `MouseEventKind`
  - `MouseButton`
  - `MouseScroll`
- Root package adds:
  - `MouseTrackingMode`
  - `Tty::enable_mouse`
  - `Tty::disable_mouse`
  - `Tty::with_mouse`

## Invariants

- Internal `EventReader` remains the low-level byte-to-event decoder.
- Root `Tty::read_event` continues to surface mouse reports through
  `Input(@input.Mouse(...))`, not as a separate root event.
- Mouse support does not introduce pointer state, hover tracking state, pixel
  coordinate conversion, or platform-specific public API.
- Unsupported mouse encodings remain unknown byte sequences.

## Acceptance

- `CSI < 0 ; 20 ; 10 M` decodes as left press at row 10, column 20.
- `CSI < 0 ; 20 ; 10 m` decodes as left release.
- Motion and wheel button codes decode to structured mouse event kinds.
- Shift, Alt, and Ctrl bits decode into existing `KeyModifiers`.
- Invalid coordinates and unsupported buttons decode as `Unknown`.
- Root command helpers emit the expected `?1006` and tracking mode sequences.
- `examples/input` can display mouse events for manual validation.

## Validation

- `moon fmt`
- `moon test internal/input`
- `moon test internal/vt`
- `moon test .`
- `moon check examples/input`
- `moon test examples/input`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added `Mouse(MouseEvent)` to `@input.InputEvent`.
- Added mouse event data types for event kind, button, scroll direction, cell
  coordinates, and key modifiers.
- Decoded SGR 1006 mouse reports into structured mouse input events.
- Kept malformed SGR mouse reports, zero coordinates, unsupported additional
  buttons, and unmodeled encodings as `Unknown`.
- Consumed legacy X10 mouse reports as fixed-width three-byte `Unknown` events
  so unsupported coordinate bytes do not leak as key input.
- Kept UTF-8 mouse mode 1005 unmodeled because it cannot be reliably
  distinguished from fixed-width X10 without terminal mode state.
- Added internal VT byte constants for SGR mouse encoding and click, drag, and
  motion tracking modes.
- Added root `Tty` methods for enabling, disabling, and scoped SGR mouse
  tracking.
- Updated `examples/input` to enable mouse motion reporting and display decoded
  mouse events.
- Updated existing examples to explicitly ignore mouse input where unsupported.

## Public API Audit

- `@input` `.mbti` adds only the intended `InputEvent::Mouse` variant,
  readable `MouseEvent`, `MouseEvent::new`, `MouseEventKind`, `MouseButton`,
  and `MouseScroll`.
- Root `.mbti` adds only `MouseTrackingMode`, `Tty::enable_mouse`,
  `Tty::disable_mouse`, and `Tty::with_mouse`.
- `internal/vt` `.mbti` adds only byte constants for xterm private mouse modes.
- Parser helpers remain private.
- No pixel-coordinate API, pointer state, platform-specific backend, screen
  model, line editor, or widget behavior was added.
- Legacy X10 reports remain unmodeled public API and are only preserved as
  unknown bytes.

## Validation Results

- `moon fmt`
- `moon test internal/input` -> 52 passed
- `moon test internal/vt` -> 14 passed
- `moon test .` -> 15 passed
- `moon check examples/input`
- `moon test examples/input` -> 6 passed
- `moon test` -> 115 passed
- `moon check`
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
