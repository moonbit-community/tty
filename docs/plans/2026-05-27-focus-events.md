# Focus Events

## Goal

Support xterm focus tracking as decoded input events and root `Tty` command
helpers, without adding terminal capability negotiation or terminal-emulator
state.

## Status

Done.

## Context And Decisions

- xterm focus tracking is enabled with private mode 1004:
  - enable: `CSI ? 1004 h`
  - disable: `CSI ? 1004 l`
- When enabled by a supporting terminal, focus reports arrive on the input byte
  stream:
  - focus in: `CSI I`
  - focus out: `CSI O`
- The decoder should recognize focus reports unconditionally. Callers decide
  whether to enable tracking; unsupported terminals are expected to ignore the
  mode switch and simply never send focus reports.
- Do not add a support probe. A DECRQM-style query would add asynchronous
  terminal replies, timeout behavior, and response/input interleaving for a mode
  that can be safely attempted.
- Keep focus reports as input events. They are not root resize events and not
  terminal response events for request/response queries.

## Proposed Design

- Add direct variants to public `@input.InputEvent`:
  - `FocusIn`
  - `FocusOut`
- Decode exact `CSI I` as `Input(FocusIn)`.
- Decode exact `CSI O` as `Input(FocusOut)`.
- Keep malformed or parameterized focus-like CSI sequences as `Unknown(Bytes)`.
- Add internal VT byte constants:
  - `enable_focus_tracking`
  - `disable_focus_tracking`
- Add root `Tty` helpers:
  - `Tty::enable_focus_tracking`
  - `Tty::disable_focus_tracking`
  - `Tty::with_focus_tracking`
- Update `examples/input` to enable focus tracking during the demo and display
  focus events.

## Why Existing Code Is Not Enough

The existing decoder has event variants for keys, mouse, paste, and unknown
bytes, but no way to represent terminal focus reports without losing semantics
as `Unknown`. The existing VT helpers cover alternate screen, bracketed paste,
mouse, SGR, cursor, and kitty keyboard modes, but do not emit private mode
1004. The bracketed paste and mouse patterns can be reused for command helper
shape, but they cannot represent focus tracking without new constants and event
variants.

## Target Files

- `docs/plans/2026-05-27-focus-events.md`
- `input/event.mbt`
- `internal/input/decoder.mbt`
- `internal/input/decoder_test.mbt`
- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `examples/input/main.mbt`
- `examples/input/main_wbtest.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files from `moon info`

## Expected Public API Diff

Expected public input package `.mbti` changes:

- `@input.InputEvent` adds `FocusIn`.
- `@input.InputEvent` adds `FocusOut`.
- No new public focus data type is proposed. A wrapper such as
  `Focus(FocusEvent)` would add another public type without carrying additional
  data.

Expected root package `.mbti` changes:

- `Tty::enable_focus_tracking(Self) -> Unit`
- `Tty::disable_focus_tracking(Self) -> Unit`
- `Tty::with_focus_tracking(Self, async () -> T) -> T`

Expected internal VT `.mbti` changes:

- `enable_focus_tracking : Bytes`
- `disable_focus_tracking : Bytes`

Expected internal input `.mbti` changes:

- No direct internal stream-event shape change. Focus reports should flow
  through the existing `Input(@input.InputEvent)` event.

## Invariants

- `EventReader` remains the only low-level byte-to-event decoder.
- Focus support does not add a line editor, screen model, widget layer,
  terminal-emulator focus state, or platform backend state.
- Root `Tty::read_event` surfaces focus reports as `Input(FocusIn)` and
  `Input(FocusOut)`.
- Terminal response query methods continue to preserve interleaved user input,
  including focus events, through the existing pending-input path.
- Unsupported terminals require no special branch; they ignore `?1004h`.

## Acceptance Criteria

- `CSI I` decodes as `Input(FocusIn)`.
- `CSI O` decodes as `Input(FocusOut)`.
- Parameterized or malformed focus-like CSI sequences decode as `Unknown`.
- Root command helpers emit `CSI ? 1004 h` and `CSI ? 1004 l`.
- `Tty::with_focus_tracking` disables focus tracking when the async body
  returns or raises.
- `examples/input` can show focus-in and focus-out events during manual
  terminal validation.
- No capability query or support-detection API is added.
- Generated `.mbti` diffs match only the intended API changes.

## Validation Plan

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

## Open Questions

- None for the proposed implementation shape. If the direct
  `FocusIn`/`FocusOut` variants are not desired, the smallest alternative is a
  `Focus(FocusEvent)` wrapper, but that would intentionally add another public
  enum.

## Next Implementation Step

Completed.

## Result

- Added `FocusIn` and `FocusOut` to public `@input.InputEvent`.
- Decoded exact `CSI I` and `CSI O` reports as focus input events.
- Kept parameterized focus-like CSI sequences as `Unknown`.
- Covered cursor-position query interleaving so focus input is preserved for a
  later root `Tty::read_event` call.
- Added internal VT byte constants for xterm private mode 1004.
- Added root `Tty` helpers for enabling, disabling, and scoped focus tracking.
- Updated `examples/input` to enable focus tracking and print decoded terminal
  events directly.
- Updated examples that match input events to explicitly ignore focus events
  where they do not act on them.

## Public API Audit

- `@input` `.mbti` adds only `InputEvent::FocusIn` and
  `InputEvent::FocusOut`.
- Root `.mbti` adds only `Tty::enable_focus_tracking`,
  `Tty::disable_focus_tracking`, and `Tty::with_focus_tracking`.
- `internal/vt` `.mbti` adds only `enable_focus_tracking` and
  `disable_focus_tracking`.
- `internal/input` `.mbti` remains unchanged; focus reports flow through the
  existing `Input(@input.InputEvent)` stream event.
- No capability query, terminal focus state cache, platform backend state,
  screen model, or line-editor behavior was added.

## Validation Results

- `moon test internal/input` -> 57 passed
- `moon test internal/vt` -> 16 passed
- `moon test .` -> 22 passed
- `moon check examples/input`
- `moon test examples/input` -> 7 passed
- `moon fmt`
- `moon test` -> 139 passed
- `moon check`
- `moon info`
- reviewed generated `.mbti` diff
- `moon check examples/pager`
- `moon check examples/agent`
- `git diff --check`
