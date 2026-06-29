# Win32 Event Reader

## Goal

Move Windows console input parsing state out of the root tty package and into
`internal/win32`, so the Win32 package owns native `INPUT_RECORD` state and
exposes a small event-reader boundary to root `Tty`.

## Target Files

- `docs/plan.md`
- `internal/win32/moon.pkg`
- `internal/win32/event_reader.mbt`
- `internal/win32/pkg.generated.mbti`
- `win32_input.mbt`
- `win32_input_wbtest.mbt`
- `moon.pkg`
- `non_windows_imports.mbt`
- `pkg.generated.mbti`

## Accepted Design

- Add `pub(all) enum Event { Input(@public_input.InputEvent); Resize }` to
  `internal/win32`.
- Add an opaque `EventReader` to `internal/win32` that owns:
  - the console input fd
  - the byte queue feeding the terminal byte decoder
  - an internal `@input.EventReader` decoder
  - a direct native-event queue
  - `pending_surrogate`
  - native mouse button state
- Move Windows console record draining and record dispatch from root
  `win32_input.mbt` into `internal/win32`.
- Move the `ReadConsoleInputW` / `sizeof(INPUT_RECORD)` native stub boundary
  into `internal/win32`.
- Keep the existing `internal/input.EventReader` as a private parser component
  of `internal/win32.EventReader`, because Windows text key records still need
  the existing UTF-8, VT sequence, bracketed paste, SGR mouse, and terminal
  response decoder.
- Keep root `Tty` responsible for backend selection, terminal handles, window
  size lookup, and public root `Event` construction.
- For root `Tty::read_event`, map `@win32.Event::Input(input)` to
  `Event::Input(input)` and `@win32.Event::Resize` to a fresh
  `Event::Resize(WindowSize)` by calling `Tty::window_size`.
- Keep non-console Windows handles on the existing byte-stream decoder path.

## Public API / Interface Diff

- Root package public API should remain unchanged.
- `input/pkg.generated.mbti`, `internal/input/pkg.generated.mbti`, and
  `internal/io/pkg.generated.mbti` should remain unchanged.
- `internal/win32/pkg.generated.mbti` should gain only the internal
  `Event` / `EventReader` API and related method declarations.
- `EventReader` remains opaque; callers outside `internal/win32` do not get
  direct access to parser state fields.

## Invariants

- Existing Windows key behavior remains unchanged:
  - key-up records are ignored
  - AltGr text records stay on the byte-decoder path
  - explicit printable modifiers preserve modifier metadata
  - keypad and keypad navigation metadata remain direct events
  - Ctrl-left-bracket and Ctrl-space remain direct key events
- Native Win32 mouse records continue to map to public mouse input events.
- Resize records are preserved as native Win32 events and surfaced by root
  `Tty::read_event` as `Resize(WindowSize)`.
- Terminal response events such as cursor position, kitty flags, primary
  device attributes, and OSC dynamic colors stay internal and are available
  through root query methods.
- The refactor does not add screen state, layout, widgets, or terminal-emulator
  state.

## Acceptance Criteria

- Root `WindowsInput::Console` no longer stores `byte_queue`,
  `pending_surrogate`, `mouse_button_state`, or direct event queue fields.
- Root Windows input code delegates console event reads and internal stream
  reads to `@win32.EventReader`.
- `internal/win32.EventReader` owns all native record parsing state.
- Existing root Win32 white-box behavior tests continue to pass.
- New or moved internal Win32 tests cover the new `EventReader` surface where
  useful.
- Root generated public interface remains unchanged after `moon info`.

## Validation Plan

- `moon fmt`
- `moon test internal/win32`
- `moon test internal/io`
- `moon test . --filter "win32*"`
- `moon test .`
- `moon check`
- `moon check --target all`
- `moon info`
- Review `.mbti` diff.
- `git diff --check`

## Result

- Added `internal/win32.Event` and an opaque `internal/win32.EventReader`.
- Moved Windows console record draining, `ReadConsoleInputW` FFI declarations,
  byte-queue ownership, direct native-event queue ownership,
  `pending_surrogate`, and native mouse state into `internal/win32`.
- Moved the Windows input native stub from the root package to
  `internal/win32`.
- Root `WindowsInput` now only selects between:
  - `ByteStream(@input.EventReader)` for non-console handles
  - `Console(@win32.EventReader)` for native console handles
- Root `Tty` no longer stores a Windows-side `reader` field; non-Windows keeps
  its existing byte-stream reader field.
- Root Windows resize events now cross the `internal/win32` boundary as
  `@win32.Event::Resize`, then root calls `Tty::window_size` to construct the
  public `Resize(WindowSize)`.
- Migrated the Windows input behavior white-box tests from the root package to
  `internal/win32`, where the parser state now lives.

## Validation Results

Completed on 2026-06-29:

- `moon fmt` - passed
- `moon check` - passed
- `moon test internal/win32` - passed, 19 tests
- `moon test internal/io` - passed, 4 tests
- `moon test . --filter "win32*"` - passed with no root test entries after
  moving the Win32 behavior tests to `internal/win32`
- `moon test .` - passed, 27 tests
- `moon check --target all` - passed
- `moon test` - passed, 184 tests
- `moon info` - passed
- `git diff --check` - passed

## Public API Audit

- Root package public API is unchanged.
- `input/pkg.generated.mbti`, `internal/input/pkg.generated.mbti`, and
  `internal/io/pkg.generated.mbti` are unchanged.
- `internal/win32/pkg.generated.mbti` has the intended internal API additions:
  - `pub(all) enum Event { Input(@input.InputEvent); Resize }`
  - opaque `EventReader`
  - `EventReader::new`
  - `EventReader::close`
  - `EventReader::read_event`
  - `EventReader::read_internal_event`
- `moon info` again surfaced the known root `Fd::fd` generated mbti spelling
  drift from `Int` to `@types.Fd`; that unrelated root generated-file change
  was restored and is not part of this task.
