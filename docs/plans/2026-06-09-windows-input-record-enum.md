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

## Follow-up: Flatten Windows Input Backend

### Goal

Make `Tty.reader` the single byte-stream `EventReader` owner on Windows by
flattening the Windows console input source state into a private Windows input
backend stored by `Tty`.

### Accepted Design

- Keep the change Windows-only and private to the root package.
- Replace `Win32ConsoleInputSource` with a private `WindowsInput` enum:
  - `ByteStream` for non-console Windows handles that should read directly from
    the original input byte stream.
  - `Console(...)` for Win32 console handles that use `ReadConsoleInputW`,
    pipe text bytes into `Tty.reader`, and queue direct events.
- Keep `Tty.reader` as the only `@input.EventReader` field.
- In the console case, construct `Tty.reader` from the console byte pipe read
  end; in the fallback case, construct it from the original input reader.
- Keep existing pipe-based byte delivery and current cancellation behavior; do
  not introduce a queue-backed byte reader in this refactor.
- Do not add Windows prefixes to `Tty` field names solely because the struct is
  under `#cfg(platform="windows")`.

### Public API / Interface Diff

- No public MoonBit API change intended.
- `pkg.generated.mbti` should remain unchanged after `moon info`.

### Validation Plan

- `moon fmt`
- `moon test . --filter "win32*" --target-dir .moon-test-win32-flatten-build`
- `moon check --target-dir .moon-check-flatten-build`
- `moon info --target-dir .moon-info-flatten-build`
- Review `.mbti` diff.

### Result

- Replaced `Win32ConsoleInputSource` with the private Windows-only
  `WindowsInput` backend enum.
- `Tty` now owns the active `EventReader` on Windows:
  - `ByteStream` uses the original input byte reader.
  - `Console` uses the console byte pipe read end.
- Moved Windows console record reading and record dispatch helpers onto `Tty`.
- Kept existing pipe-based text-byte delivery and direct event queue behavior.

### Validation Results

- Passed: `moon fmt`
- Passed: `moon check --target-dir .moon-check-flatten-build`
- Passed: `moon test . --filter "win32*" --target-dir .moon-test-win32-flatten-build`
- Passed: `moon info --target-dir .moon-info-flatten-build`
- Note: `moon info` still rewrites the pre-existing `Fd::fd` generated mbti
  spelling from `Int` to `@types.Fd`; this flatten refactor does not intend to
  include that generated public-interface churn.

## Follow-up: Split Win32 Input Parser Package

### Goal

Move the pure Windows `INPUT_RECORD` parsing and native key/mouse mapping code
out of the root tty package into `internal/win32`, while keeping root `Tty`
responsible for terminal handles, backend selection, async record reading, and
platform FFI.

### Accepted Design

- Add a new internal package at `internal/win32`.
- Move raw input record modeling, byte-layout parsing, key mapping, mouse
  mapping, modifier mapping, and surrogate helpers into that package.
- Use package-local names without redundant `Win32` prefixes where the package
  path already supplies the Win32 context:
  - `RawInputRecord`
  - `InputRecord`
  - `KeyRecord`
  - `MouseRecord`
  - `MouseButtonState`
- Keep `ReadConsoleInputW` and `sizeof(INPUT_RECORD)` FFI wrappers in the root
  tty package. Root passes an `@win32.RawInputRecord` buffer to C and then asks
  the internal package to parse it.
- Keep the current pipe-based text-byte delivery and direct event queue
  behavior unchanged.
- Keep root tests for `Tty`/backend behavior in the root white-box test file,
  and move raw record layout tests to `internal/win32`.

### Public API / Interface Diff

- No root public MoonBit API change intended.
- Root `pkg.generated.mbti` should remain unchanged after `moon info`.
- The new `internal/win32` package will expose an internal-only interface for
  root tty code and white-box tests.

### Validation Plan

- `moon fmt`
- `moon test internal/win32 --target-dir .moon-test-internal-win32-build`
- `moon test . --filter "win32*" --target-dir .moon-test-win32-split-build`
- `moon check --target-dir .moon-check-win32-split-build`
- `moon info --target-dir .moon-info-win32-split-build`
- Review `.mbti` diff.
- `git diff --check`

### Result

- Added `internal/win32` for pure Windows `INPUT_RECORD` modeling, parsing,
  key mapping, mouse mapping, and modifier/surrogate helpers.
- Root `win32_input.mbt` now keeps only the Windows input backend, `Tty`
  dispatch helpers, and the `ReadConsoleInputW` / `sizeof(INPUT_RECORD)` FFI
  wrapper.
- Root passes an `@win32.RawInputRecord` buffer to C and parses it through the
  internal package.
- Moved raw record layout white-box tests into `internal/win32`.
- Kept root white-box tests focused on `Tty` backend behavior.

### Validation Results

- Passed: `moon fmt`
- Passed: `moon test internal/win32 --target-dir .moon-test-internal-win32-build`
- Passed: `moon test . --filter "win32*" --target-dir .moon-test-win32-split-build`
- Passed: `moon check --target-dir .moon-check-win32-split-build`
- Passed: `moon info --target-dir .moon-info-win32-split-build`
- Passed: `git diff --check`
- Note: `moon info` still rewrites the pre-existing root `Fd::fd` generated
  mbti spelling from `Int` to `@types.Fd`; this split restored the root
  generated interface to avoid unrelated public API churn.
