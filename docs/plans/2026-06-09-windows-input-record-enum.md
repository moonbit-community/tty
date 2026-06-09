# Windows Input Record Enum

## Goal

Parse Windows console `INPUT_RECORD` values on the MoonBit side as a private
record enum, and handle native mouse records produced by `ReadConsoleInputW`.

## Target Files

- `win32_input.c`: copy one Windows `INPUT_RECORD` into a caller-provided byte
  buffer instead of flattening selected fields into many FFI refs.
- `win32_input.mbt`: parse the raw Windows record layout into a private enum
  and dispatch key, mouse, focus, and resize records through typed variants.
- `win32_input_wbtest.mbt`: update helpers and add record-layout and mouse
  regression coverage.
- `docs/plan.md`: mark the task active while this implementation is in flight.

## Accepted Design

- Keep the implementation Windows-only and private to the root package.
- Treat the Windows SDK `INPUT_RECORD` layout as the private on-Windows ABI
  boundary.
- The C FFI reads with `PeekConsoleInputW` / `ReadConsoleInputW` and copies the
  resulting `INPUT_RECORD` bytes into a MoonBit-owned buffer.
- MoonBit parses that buffer into:
  - `Win32InputRecord::Key(Win32KeyRecord)`
  - `Win32InputRecord::Mouse(Win32MouseRecord)`
  - `Win32InputRecord::WindowBufferSize(Win32Coord)`
  - `Win32InputRecord::Focus(Bool)`
  - `Win32InputRecord::Unsupported(Int)`
- Existing key-record behavior is preserved while moving from the old flat
  record struct to the `Key` payload.
- Native `MOUSE_EVENT_RECORD` values map to existing public
  `@input.MouseEvent` values and are queued as `Input(Mouse(...))`.
- Keep SGR/VT mouse byte decoding unchanged for terminals that report mouse
  input as VT sequences.
- The direct-event vs decoded-byte select lives inside
  `Win32ConsoleInputSource::read_decoded_input_event`.
- `Win32ConsoleInputSource::read_event` starts the record producer and delegates
  event selection to `read_decoded_input_event`.

## Public API / Interface Diff

- No public MoonBit API change.
- `pkg.generated.mbti` should remain unchanged after `moon info`.
- New enum, record payload types, byte-layout helpers, and FFI functions remain
  private to the root package.

## Invariants

- C does not expose raw `INPUT_RECORD` memory beyond copying it into a buffer
  supplied by MoonBit.
- MoonBit layout parsing is guarded by buffer-size checks and stays under
  `#cfg(platform="windows")`.
- Unsupported record types are still consumed and ignored so they cannot stall
  polling.
- Key repeats, AltGr text, keypad metadata, Ctrl-space, Ctrl-left-bracket,
  key-up dropping, and query-source preservation remain unchanged.
- This task does not change the existing pipe-based byte delivery or attempt to
  solve cancellation after `ReadConsoleInputW` consumes a record.

## Acceptance Criteria

- Existing Windows key/focus/resize white-box tests continue to pass.
- New tests prove the raw Windows record bytes parse into typed enum variants.
- New tests prove native mouse move/button records become public mouse events.
- `examples/input` should no longer lose native mouse records through the
  unsupported-record branch on Windows console input.

## Validation Plan

- `moon fmt`
- Targeted Windows white-box tests for input-record parsing and mouse mapping.
- Existing targeted Windows input-source regression tests.
- `moon test .`
- `moon test`
- `moon check`
- `moon check --target all`
- `moon info`
- Review `.mbti` diff.
- `git diff --check`

## Result

- Implemented the private Windows record split:
  - C now copies the SDK `INPUT_RECORD` bytes into a MoonBit-owned buffer.
  - MoonBit parses those bytes into private `Key`, `Mouse`,
    `WindowBufferSize`, `Focus`, and `Unsupported` variants.
  - Existing key handling now consumes `Win32KeyRecord`.
  - Native `MOUSE_EVENT_RECORD` values update a mutable
    `Win32MouseButtonState` and queue existing public `MouseEvent` values.
- Added white-box coverage for raw key, mouse, and focus record parsing.
- Added white-box coverage for native mouse move, press, drag, release, and
  wheel mapping.
- Moved the direct-event vs decoded-input select into
  `Win32ConsoleInputSource::read_decoded_input_event`, without changing the
  existing pipe-based byte delivery.

## Validation Results

- Passed: `moon fmt`
- Passed: `moon test . --filter "win32*" --target-dir .moon-test-win32-build`
- Passed: `moon check --target-dir .moon-check-build`
- Passed: `moon test . --target-dir .moon-test-dot-build`
- Passed: `moon test --target-dir .moon-test-all-build`
- Passed: `moon check --target all --target-dir .moon-check-all-build`
- Passed: `moon info --target-dir .moon-info-build`
- Passed: `clang.exe -fsyntax-only -I C:\Users\mbt\.moon\include win32_input.c`
- Passed: `git diff --check`
- Note: full native test runs emit warnings from upstream async/runtime C stubs
  on Windows; no warnings remain from this package's MoonBit changes.
- Re-ran after the select-only follow-up:
  - Passed: `moon fmt`
  - Passed: `moon test . --filter "win32*" --target-dir .moon-test-win32-build`
  - Passed: `moon check --target-dir .moon-check-build`
  - Note: `moon check` currently reports private unused-field warnings for the
    Windows `INPUT_RECORD` enum payloads.

## Public API Audit

- No public MoonBit API change intended.
- `moon info` produced no intended `.mbti` public API diff.
