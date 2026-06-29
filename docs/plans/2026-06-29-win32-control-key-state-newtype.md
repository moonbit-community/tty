# Win32 Control Key State Newtype

## Goal

Represent Win32 `dwControlKeyState` values with a dedicated
`ControlKeyState` newtype instead of passing raw `Int` values through record
fields and decoding helpers.

## Target Files

- `internal/win32/record.mbt`
- `internal/win32/key.mbt`
- `internal/win32/mouse.mbt`
- `internal/win32/control_key_state.mbt`
- `internal/win32/record_wbtest.mbt`
- `internal/win32/pkg.generated.mbti`

## Public API Changes

- Add `pub struct ControlKeyState(Int)` to `internal/win32`.
- Add `pub fn ControlKeyState::has_state(ControlKeyState, Int) -> Bool`.
- Add private `ControlKeyState::modifiers(ControlKeyState) -> KeyModifiers`.
- Change `KeyRecord.control_key_state` from `Int` to `ControlKeyState`.
- Change `MouseRecord.control_key_state` from `Int` to `ControlKeyState`.
- Keep `KeyRecord::new(... control_key_state? : Int = 0)` unchanged.
- Keep `MouseRecord::new(... control_key_state? : Int = 0)` unchanged.
- Keep Win32 control key mask constants as `Int`.
- Root package public API should remain unchanged.

## Invariants

- Existing key and mouse decoding behavior must not change.
- Parsed Win32 `INPUT_RECORD` bytes must preserve the same control-key bits.
- AltGr handling must still treat `RightAltPressed | LeftCtrlPressed` as text
  input unless left Alt or right Ctrl is also present.
- Key modifiers and key event state should be derived through
  `ControlKeyState` methods.

## Acceptance Criteria

- `internal/win32` no longer has a package-level `has_state(Int, Int)` helper.
- `internal/win32` no longer has a package-level
  `modifiers_from_control_key_state` helper.
- All record fields storing Win32 control-key bits use `ControlKeyState`.
- Existing callers can still pass raw `Int` masks to `KeyRecord::new` and
  `MouseRecord::new`.
- `.mbti` changes are limited to the intended `internal/win32` API diff.

## Validation

Completed on 2026-06-29:

- `moon fmt` - passed
- `moon test internal/win32` - passed, 7 tests
- `moon test .` - passed, 39 tests; emitted existing dependency C warnings
- `moon check` - passed
- `moon info` - passed
- `git diff --check` - passed

## Public API Audit

- Intended `internal/win32` interface changes:
  - added `ControlKeyState`
  - added `ControlKeyState::has_state`
  - changed `KeyRecord.control_key_state` to `ControlKeyState`
  - changed `MouseRecord.control_key_state` to `ControlKeyState`
- `KeyRecord::new` and `MouseRecord::new` still accept `Int` masks for
  `control_key_state`.
- `ControlKeyState::modifiers` remains package-private.
- Root package source was not changed. `moon info` also surfaced a
  pre-existing root `pkg.generated.mbti` drift for `Fd::fd`; that unrelated
  generated-file change was not retained in this task.
