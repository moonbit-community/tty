# SGR Attributes

## Goal

Add command-style support for common SGR text attributes while keeping this
package below rich text rendering and terminal style state.

## Status

Done.

## Design

- Add fixed SGR byte values in `tonyfettes/tty/vt` for:
  - bold / normal intensity
  - italic / not italic
  - underline / not underlined
  - reverse video / positive image
- Add matching root `Tty` methods that directly write those bytes.
- Keep `vt` byte-only and output-stream agnostic.
- Do not add a style value type, builder, parser state, terminal capability
  detection, renderer, or layout abstraction.
- Keep `tonyfettes/tty/color` scoped to semantic color values.

## Target Files

- `vt/sgr.mbt`
- `vt/sgr_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- `examples/color/main.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- generated `.mbti` files

## Public API Changes

Add to `tonyfettes/tty/vt`:

- `bold : Bytes`
- `reset_bold : Bytes`
- `italic : Bytes`
- `reset_italic : Bytes`
- `underline : Bytes`
- `reset_underline : Bytes`
- `reverse : Bytes`
- `reset_reverse : Bytes`

Add to root `Tty`:

- `Tty::bold(Self) -> Unit`
- `Tty::reset_bold(Self) -> Unit`
- `Tty::italic(Self) -> Unit`
- `Tty::reset_italic(Self) -> Unit`
- `Tty::underline(Self) -> Unit`
- `Tty::reset_underline(Self) -> Unit`
- `Tty::reverse(Self) -> Unit`
- `Tty::reset_reverse(Self) -> Unit`

## Invariants

- Attribute methods do not track current terminal style.
- `reset_bold` writes SGR 22, which means normal intensity and therefore also
  clears faint intensity in terminals that support it.
- `reset_style` remains the all-SGR reset.
- `vt` remains independent from root `Tty`, `color`, and async I/O.

## Acceptance

- Low-level `vt` constants emit the expected SGR bytes.
- Root `Tty` methods emit the same bytes in order.
- The color specimen demo can show the new text attributes.
- Generated `.mbti` diffs contain only the intended public APIs.

## Validation

- `moon fmt`
- `moon test vt`
- `moon test .`
- `moon check examples/color`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added fixed SGR byte values for bold, italic, underline, reverse video, and
  their targeted resets in `tonyfettes/tty/vt`.
- Added matching root `Tty` command methods that write those bytes directly.
- Updated the color specimen demo to include an attribute row.
- Updated README and architecture notes to include text attributes in the
  low-level command surface.

## Public API Audit

- `tonyfettes/tty/vt` adds only the intended eight public byte constants.
- Root `Tty` adds only the intended eight async command methods.
- No new public types, mutable fields, parser states, dependencies, platform
  files, backend selection, capability detection, or style-state model were
  introduced.
- `reset_bold` intentionally maps to SGR 22 normal intensity, matching the
  terminal protocol rather than tracking a local bold flag.

## Validation Results

- `moon fmt`
- `moon test vt` -> 12 passed
- `moon test .` -> 11 passed
- `moon check examples/color`
- `moon test` -> 97 passed
- `moon check`
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
