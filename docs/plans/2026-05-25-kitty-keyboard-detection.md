# Kitty Keyboard Detection

## Goal

Detect kitty keyboard protocol support through terminal response events before
adding enhanced keyboard input mode.

## Status

Done.

## Context And Decisions

- kitty keyboard protocol support should be detected with the documented query:
  `CSI ? u`, followed by a primary device attributes request `CSI c` as the
  response boundary.
- A terminal that supports the protocol replies with `CSI ? flags u`.
- A terminal that does not support the protocol may still reply to the primary
  device attributes request with `CSI ? ... c`; if that arrives before a
  keyboard flags reply, the protocol is treated as unsupported.
- These replies are terminal responses, not user input. They belong beside the
  existing low-level cursor-position response event rather than being parsed out
  of `Unknown` by root query code.
- This task only adds detection. Enhanced key decoding and scoped mode
  enable/disable belong to a follow-up plan.

## References Or Standards

- kitty keyboard protocol progressive enhancement query and primary device
  attributes fallback: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
- ECMA-48 primary device attributes response shape: `CSI ? ... c`.

## Target Files

- `docs/plan.md`
- `docs/architecture.md`
- `README.md`
- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `internal/input/event.mbt`
- `internal/input/decoder.mbt`
- `internal/input/decoder_test.mbt`
- `tty.mbt`
- `tty_wbtest.mbt`
- generated `.mbti` files

## Public API Changes

- Internal input stream `Event` adds `KeyboardEnhancementFlags(Int)`.
- Internal input stream `Event` adds `PrimaryDeviceAttributes(Bytes)`.
- Root `Tty` adds `query_kitty_keyboard_support(timeout_ms?) -> Bool`.
- `internal/vt` adds keyboard enhancement status and primary device attributes
  query byte constants for root implementation use.

## Invariants

- `EventReader` remains the only low-level byte-to-event decoder.
- Terminal response events do not become root `Tty::read_event` events.
- Root query methods preserve interleaved user input for later
  `Tty::read_event` calls.
- Detection does not add a screen model, line editor, keyboard mode state, or
  terminal emulator state.
- Enhanced kitty `CSI u` key decoding remains out of scope for this task.

## Acceptance Criteria

- `CSI ? 1 u` decodes as `KeyboardEnhancementFlags(1)`.
- `CSI ? 1 ; 2 c` decodes as `PrimaryDeviceAttributes(...)`.
- Invalid private CSI shapes still decode as `Input(Unknown(bytes))`.
- `Tty::query_kitty_keyboard_support` writes `CSI ? u` and `CSI c`.
- The root query returns `true` when a keyboard flags reply arrives first.
- The root query returns `false` when a primary device attributes reply arrives
  first or the query times out.
- User input read while waiting for the query response is preserved.

## Validation Commands

- `moon fmt`
- `moon test internal/input`
- `moon test internal/vt`
- `moon test .`
- `moon check examples/input`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Public API Audit

- Internal input stream `Event` adds `KeyboardEnhancementFlags(Int)` so root
  query code can observe kitty keyboard progressive enhancement status replies
  without treating them as user input.
- Internal input stream `Event` adds `PrimaryDeviceAttributes(Bytes)` so root
  query methods can use DA1 as a documented response boundary while preserving
  the raw reply inside the internal decoder layer.
- Root `Tty` adds `query_kitty_keyboard_support(timeout_ms?) -> Bool` for the
  common consumer story: decide whether it is safe to enable enhanced keyboard
  mode.
- `internal/vt` adds query byte constants used by root `Tty`; this package is
  internal and remains byte-only.
- No `KeyEvent`, `KeyCode`, or `KeyModifiers` public shape changed.
- Parser helpers and private CSI parsing details remain internal.
- Generated `.mbti` diff was reviewed after `moon info`.

## Result Notes

- Added low-level stream events for `CSI ? flags u` and `CSI ? ... c`.
- Added root support detection that writes `CSI ? u` and `CSI c`.
- The root query returns `true` for keyboard enhancement flags, `false` for DA1
  or timeout, and preserves interleaved user input in `pending_input`.
- Root `Tty::read_event` continues to suppress terminal response events from the
  public root event stream.
- Updated README and architecture notes for the new terminal response events and
  query method.

## Validation Results

- `moon test internal/input` -> 46 passed
- `moon test internal/vt` -> 13 passed
- `moon test .` -> 13 passed
- `moon fmt`
- `moon check examples/input`
- `moon test` -> 105 passed
- `moon check`
- `moon info`
- reviewed generated `.mbti` diff
- `git diff --check`

## Open Questions

- Whether the follow-up enhanced key decoding should expose kitty event type
  and alternate-key data or initially map only safe subsets into existing
  `KeyEvent`.
