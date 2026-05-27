# OSC Dynamic Color Queries

## Goal

Support xterm OSC 10/11/12 queries for the terminal default foreground,
default background, and text cursor colors, without adding palette mutation,
terminal color capability detection, or terminal-emulator state.

## Status

Done.

## Context And Decisions

- OSC 10, 11, and 12 are xterm dynamic-color controls:
  - 10: VT100 text foreground color
  - 11: VT100 text background color
  - 12: text cursor color
- Sending `Pt = ?` asks the terminal to reply with a control sequence that can
  set the corresponding value.
- OSC replies are terminal response traffic on the input byte stream. They
  should be consumed by root query methods, like cursor-position reports and
  kitty keyboard detection replies, rather than surfaced as public input events.
- Accept both BEL and ST string terminators when decoding OSC replies.
- Represent returned RGB components as 16-bit `0..65535` values because
  XParseColor `rgb:R/G/B` components can carry 1 to 4 hexadecimal digits per
  component. Do not silently reduce query results to 8-bit color.
- Approved API adjustment: expose that 16-bit RGB value as `@color.Rgb16`
  rather than a root `TerminalColor`, so the value type lives with terminal
  color values while terminal-state querying remains on root `Tty`.
- This task does not add OSC setters or resets. Those mutate terminal dynamic
  colors and deserve a separate API decision if needed.

## References Or Standards

- xterm control sequences: OSC text parameters and dynamic colors.
  https://www.invisible-island.net/xterm/ctlseqs/ctlseqs.html
- Xlib RGB device string syntax used by XParseColor.
  https://tronche.com/gui/x/xlib/color/strings/rgb.html

## Target Files

- `docs/plans/2026-05-27-osc-dynamic-colors.md`
- `docs/plan.md`
- `docs/architecture.md`
- `README.md`
- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `internal/input/event.mbt`
- `internal/input/decoder.mbt`
- `internal/input/decoder_test.mbt`
- `color/color.mbt`
- `color/color_test.mbt`
- `tty.mbt`
- `tty_wbtest.mbt`
- generated `.mbti` files from `moon info`

## Expected Public API Diff

Expected root package `.mbti` changes:

- Add `Tty::query_default_foreground_color(Self, timeout_ms? : Int) ->
  @color.Rgb16?`.
- Add `Tty::query_default_background_color(Self, timeout_ms? : Int) ->
  @color.Rgb16?`.
- Add `Tty::query_cursor_color(Self, timeout_ms? : Int) -> @color.Rgb16?`.

Expected internal input `.mbti` changes:

- Add an internal terminal-response event for OSC dynamic color replies.

Expected internal VT `.mbti` changes:

- Add byte constants for OSC 10/11/12 color queries.

Expected color package `.mbti` changes:

- Add `Rgb16` with readable and constructible 16-bit RGB fields.
- `moonbit-community/tty/color` remains independent from output streams and
  does not own terminal state queries.

## Invariants

- `EventReader` remains the only low-level byte-to-event decoder.
- Terminal response events do not become root `Tty::read_event` events.
- Root query methods preserve interleaved user input for later
  `Tty::read_event` calls.
- `internal/vt` remains byte-only and owns no output stream.
- The task does not add palette mutation, color capability detection, screen
  state, or terminal emulator state.

## Acceptance Criteria

- OSC 10/11/12 `rgb:R/G/B` replies terminated by BEL decode as internal dynamic
  color responses.
- OSC 10/11/12 `rgb:R/G/B` replies terminated by ST decode as internal dynamic
  color responses.
- XParseColor-style 1 to 4 hex digit RGB components are scaled to 16-bit values.
- Malformed OSC dynamic color replies remain `Input(Unknown(bytes))`.
- Root query methods write the expected OSC query bytes.
- Root query methods return `Some(@color.Rgb16)` when the matching response is
  received and `None` on timeout.
- User input read while waiting for a color response is preserved.
- Generated `.mbti` diffs match only the intended API changes.

## Validation Plan

- `moon fmt`
- `moon test color`
- `moon test internal/vt`
- `moon test internal/input`
- `moon test .`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Open Questions

- None for the approved query-only scope. OSC dynamic color setters/resets are
  intentionally left for a separate design if needed.

## Next Implementation Step

Completed.

## Result

- Added OSC 10/11/12 query byte constants to `internal/vt`.
- Added OSC string decoding to the internal input stream decoder, accepting BEL
  and ST terminators.
- Decoded OSC 10/11/12 `rgb:R/G/B` replies into an internal
  `DynamicColor(code~, red~, green~, blue~)` terminal-response event.
- Scaled XParseColor-style RGB components with 1 to 4 hexadecimal digits to
  16-bit values.
- Added `@color.Rgb16` and root query methods for default foreground, default
  background, and text cursor colors.
- Preserved interleaved user input while root color queries wait for matching
  OSC replies.

## Public API Audit

- Root `.mbti` adds only `Tty::query_default_foreground_color`,
  `Tty::query_default_background_color`, and `Tty::query_cursor_color`.
- `moonbit-community/tty/color` `.mbti` adds only `Rgb16` with readable and
  constructible 16-bit RGB fields.
- Internal input `.mbti` adds only the `DynamicColor` terminal-response event.
- Internal VT `.mbti` adds only the OSC 10/11/12 query byte constants.
- No OSC setters, resets, palette mutation API, color capability detection, or
  terminal state cache was added.

## Validation Results

- `moon test internal/vt` -> 16 passed
- `moon test color` -> 1 passed
- `moon test internal/input` -> 60 passed
- `moon test .` -> 23 passed
- `moon fmt`
- `moon test` -> 143 passed
- `moon check`
- `moon info`
- reviewed generated `.mbti` diff
- `git diff --check`
