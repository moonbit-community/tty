# Input Visibility Facade

## Goal

Move the byte-stream input decoder behind an internal package boundary and keep
public event APIs focused on user-facing terminal events.

## Status

Done.

## Context And Decisions

- The low-level decoder needs terminal response events for coordinated terminal
  protocols such as cursor position reports and kitty keyboard detection.
- Those terminal responses are not user input and should not become part of the
  public event stream that downstream applications usually match.
- MoonBit `internal/` packages can hide implementation-only decoder events from
  downstream callers.
- MoonBit `pub using` can re-export selected types, but does not re-export enum
  variants in the shape this package needs. Therefore the existing public
  `moonbit-community/tty/input` package remains the actual owner of user input
  values rather than a pure re-export wrapper.
- Root `moonbit-community/tty` uses the public input model for root events and
  the internal decoder model for terminal response coordination.

## References Or Standards

- MoonBit `internal/` package rule: packages under `internal/` are only
  importable by the parent package tree.
- MoonBit `pub using` re-export support for curated facades.

## Target Files

- `docs/plan.md`
- `docs/architecture.md`
- `README.md`
- `moon.pkg`
- `input/`
- `internal/input/`
- `tty.mbt`
- `tty_wbtest.mbt`
- generated `.mbti` files

## Public API Changes

- `moonbit-community/tty/input` no longer exposes `Event` or `EventReader`.
- `moonbit-community/tty/input` continues to own and expose user input values:
  `InputEvent`, `KeyEvent`, `KeyCode`, `KeyModifier`, and `KeyModifiers`.
- Root `Tty::read_event` continues to expose only root `Event`, where
  user input is represented as `Input(@input.InputEvent)`.
- Terminal response events such as cursor-position reports, kitty keyboard
  enhancement flags, and primary device attributes replies become internal
  decoder events.

## Invariants

- The root package owns terminal coordination for request/response traffic.
- Internal decoder events are not downstream API.
- User input values remain reusable by examples and downstream callers.
- Root query methods preserve interleaved user input for later
  `Tty::read_event` calls.
- No line editor, screen model, or terminal emulator state is added.

## Acceptance Criteria

- Root `Tty::query_cursor_position` and `Tty::query_kitty_keyboard_support`
  still pass existing tests.
- Public `input/pkg.generated.mbti` contains user input model types but not
  `EventReader` or terminal response events.
- Root `pkg.generated.mbti` references the public input model and contains no
  internal decoder event type.
- `internal/input/pkg.generated.mbti` contains the decoder and rich stream
  events for root package use.
- Existing examples continue to type-check.

## Validation Commands

- `moon fmt`
- `moon test internal/input`
- `moon test input`
- `moon test .`
- `moon check examples/input`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Public API Audit

- `moonbit-community/tty/input` no longer exposes `Event` or `EventReader`.
- `moonbit-community/tty/input` still exposes `InputEvent`, `KeyEvent`,
  `KeyCode`, `KeyModifier`, and opaque `KeyModifiers` with its existing
  accessors.
- Root `moonbit-community/tty.Event` still exposes user input as
  `Input(@input.InputEvent)` and resize as `Resize(WindowSize)`.
- Root `Tty` adds `query_kitty_keyboard_support(timeout_ms?) -> Bool` from the
  kitty detection task.
- `moonbit-community/tty/internal/input` exposes `EventReader` and rich stream
  `Event` only inside the module's internal package boundary.
- Parser helpers, decoder buffers, and terminal response events do not appear in
  downstream public `.mbti`.
- Generated `.mbti` diff was reviewed after `moon info`.

## Result Notes

- Moved the byte-stream decoder files from `input/` to `internal/input/`.
- Kept public user input value definitions in `input/` because `pub using` does
  not re-export enum variants in the shape needed by existing callers.
- Root `Tty` now imports public input values and the internal decoder
  separately.
- Existing examples continue to use `moonbit-community/tty/input` for user
  input pattern matching.
- Updated README and architecture docs to describe public input values and the
  internal decoder boundary.

## Validation Results

- `moon check`
- `moon test internal/input` -> 46 passed
- `moon test input` -> no test entry found, 0 passed
- `moon test .` -> 13 passed
- `moon fmt`
- `moon check examples/input`
- `moon test` -> 105 passed
- `moon check`
- `moon info`
- `moon test internal/vt` -> 13 passed
- reviewed generated `.mbti` diff
- `git diff --check`

## Open Questions

- Whether a future major release should remove the public `input` facade and
  make the root package the only user-facing event API.
