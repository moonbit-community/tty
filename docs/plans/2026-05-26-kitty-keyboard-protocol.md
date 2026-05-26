# Kitty Keyboard Protocol Support

## Goal

Add proper kitty keyboard protocol support for enhanced keyboard input:

- opt-in progressive enhancement flags on `Tty`
- press, repeat, and release key event kinds
- kitty modifier bits and lock/keypad state where the public event model can
  preserve them
- alternate key metadata (`shifted_code` and `base_code`)
- associated text via the existing `KeyEvent.text`
- `CSI u` decoding for kitty keyboard reports and kitty event-type extensions
  on legacy functional-key reports

## Background

Kitty keyboard reports use progressive flags. The relevant flags are:

- `1`: disambiguate escape codes
- `2`: report event types
- `4`: report alternate keys
- `8`: report all keys as escape codes
- `16`: report associated text

The full `CSI u` shape is:

```text
CSI unicode-key-code : shifted-key : base-key ; modifiers : event-type ; text... u
```

Modifiers are encoded as `1 + bitmask`, where the bitmask includes Shift, Alt,
Ctrl, Super, Hyper, Meta, CapsLock, and NumLock. Event type defaults to press;
`2` is repeat and `3` is release.

## Target Files

- `docs/plans/2026-05-26-kitty-keyboard-protocol.md`
- `input/event.mbt`
- `internal/input/decoder.mbt`
- `internal/input/decoder_test.mbt`
- `internal/vt/screen.mbt`
- `internal/vt/screen_test.mbt`
- `style.mbt`
- `tty_wbtest.mbt`
- generated `.mbti` files from `moon info`

## Public API Changes

Expected root package `.mbti` changes:

- add `KeyboardEnhancementFlags`
- add `Tty::push_keyboard_enhancement_flags`
- add `Tty::pop_keyboard_enhancement_flags`
- add `Tty::with_keyboard_enhancements`
- optional convenience helper `Tty::with_kitty_keyboard`

Expected public input package `.mbti` changes:

- add `KeyEventKind { Press, Repeat, Release }`
- add `KeyEventState` opaque bitset with constructor/accessors for keypad,
  caps lock, and num lock
- extend `KeyEvent` fields with:
  - `kind : KeyEventKind`
  - `state : KeyEventState`
  - `shifted_code : KeyCode?`
  - `base_code : KeyCode?`
- extend `KeyEvent::new` with optional labeled parameters for those fields
- extend `KeyModifiers` with Super and Hyper
- extend `KeyCode` for kitty functional keys that have no existing variant,
  including F13-F35, lock keys, print screen, pause, menu, keypad keys, and
  modifier keys if parser support requires preserving those reports

Expected internal VT `.mbti` changes:

- add helpers for pushing and popping keyboard enhancement flags

Internal input `.mbti` may remain limited to existing stream events unless a
private parser helper accidentally leaks; parser helpers should stay private.

## Design Shape

`KeyboardEnhancementFlags` should be an opaque bitset rather than public record
fields. It needs named constructors/accessors so callers can build presets
without relying on raw bit layout. Keep a raw `bits()` accessor if tests and
advanced callers need to inspect terminal replies later.

`KeyEvent.kind` defaults to `Press` so existing caller code that constructs
`KeyEvent::new(code)` remains source-compatible except for `.mbti` field
visibility changes caused by the new public fields.

`KeyEvent.text` remains the associated text carrier. `shifted_code` and
`base_code` are separate optional key identities, not text.

Kitty lock-state bits become `KeyEventState`, not `KeyModifiers`, because they
are keyboard state rather than modifiers a caller normally matches as a chord.

## Why Existing Code Is Not Enough

The current decoder only parses semicolon-separated CSI parameters and xterm
modifier encoding. Kitty requires colon subparameters, a distinct modifier
bitset, event types, alternate key metadata, and associated text codepoints.

The current public `KeyEvent` can only represent a press-like key with
Shift/Alt/Ctrl/Meta modifiers and optional text. It cannot faithfully preserve
repeat/release, Super/Hyper, lock/keypad state, shifted key identity, or
base-layout identity.

## Parser Scope

The first implementation should:

- decode `CSI ... u` reports
- decode kitty event-type extensions on existing direct CSI and CSI `~`
  functional-key reports
- map known functional codes into `KeyCode`
- return `Unknown(bytes)` for malformed reports or unsupported shapes instead
  of dropping information
- preserve existing legacy decoding behavior when kitty enhancements are not
  enabled

## Acceptance Criteria

- Existing tests continue to pass.
- `KeyEvent::new` defaults still construct press events with empty state.
- `CSI 97u` decodes as `Char('a')` with text `"a"`.
- `CSI 97;1:2u` decodes as repeat `a`.
- `CSI 97;1:3u` decodes as release `a`.
- `CSI 105;5u` decodes as Ctrl+i, distinct from Tab.
- `CSI 61:43;6u` preserves `code = '='`, `shifted_code = '+'`,
  `modifiers = Shift|Ctrl`.
- `CSI 0;;229u` decodes associated text as `"å"` with a text-like key event.
- Push/pop keyboard enhancement methods emit kitty-compatible bytes.
- `.mbti` diffs match the intended public API.

## Validation

Run:

```sh
moon fmt
moon test internal/input
moon test internal/vt
moon test
moon check
moon info
git diff --check
```

Review generated `.mbti` diffs before final handoff.

## Result

Implemented.

Validation completed:

- `moon fmt`
- `moon test internal/input/csi`
- `moon test internal/input/kitty`
- `moon test internal/input`
- `moon test internal/vt`
- `moon test`
- `moon check`
- `moon info`
- `git -c core.whitespace=-blank-at-eof diff --check`

All tests passed.

`git diff --check` was also run. It reports the EOF blank lines generated by
`moon info` in newly added internal `.mbti` files; those generated blanks are
kept so CI's `moon info` plus `git diff --exit-code` check stays clean.

## Public API Audit

Intentional root package API additions:

- `KeyboardEnhancementFlags`
- `KeyboardEnhancementFlags::new`
- `KeyboardEnhancementFlags::disambiguate`
- `KeyboardEnhancementFlags::full`
- `KeyboardEnhancementFlags::bits`
- `KeyboardEnhancementFlags` flag accessors
- `Tty::push_keyboard_enhancement_flags`
- `Tty::pop_keyboard_enhancement_flags`
- `Tty::with_keyboard_enhancements`
- `Tty::with_kitty_keyboard`

Intentional public input API additions:

- `KeyEventKind`
- `KeyEvent.kind`
- `KeyEventState`
- `KeyEvent.state`
- `KeyEvent.shifted_code`
- `KeyEvent.base_code`
- Super/Hyper modifier support
- kitty functional key-code variants, media key-code variants, and modifier
  key-code variants
- removed the unused single-value `KeyModifier` enum; callers use the opaque
  `KeyModifiers` set and accessors instead
- use the `super_` label/accessor spelling because `super` is reserved
  for possible future language use and produces compiler warnings

`KeyEvent::new` keeps the original `code`, `modifiers?`, and `text?` parameter
order, with new optional labeled parameters appended after `text?`.

Intentional internal VT API additions:

- `push_keyboard_enhancement_flags`
- `pop_keyboard_enhancement_flags`

Internal parser helpers remain private and do not appear in
`internal/input/pkg.generated.mbti`.

Parser cleanup:

- `CSI ... u` parsing now uses private `KittyKeyFields` and
  `KittyModifierReport` records for protocol-shaped intermediate state
- the mandatory kitty `unicode-key-code` field is matched explicitly and no
  longer falls back to a default value when omitted
- kitty-specific input parsing moved into `internal/input/kitty` so the main
  stream decoder only owns CSI framing, dispatch, and Unknown fallback
- CSI parameter parsing moved into `internal/input/csi` so semicolon parameters,
  colon subparameters, decimal parameters, and DA1 parameter validation are
  tested separately from stream-event decoding

Review follow-up:

- keep legacy CSI key modifier decoding separate from kitty CSI-u decoding so
  legacy Meta reports do not become Super
- treat kitty modifier/key/text payloads as strict protocol shapes and preserve
  malformed reports as `Unknown`
- preserve protocol-reported modifier state for explicit modifier-key events,
  including release events
- avoid synthesizing kitty text from unshifted key codes when Shift is active
  and no associated or shifted text is available
- reject control codepoints in kitty associated text while still preserving
  valid non-control scalars such as combining marks
- reject present-but-empty kitty modifier/event subparameters such as `:2`,
  `5:`, and `:`, while preserving whole-field defaulting for omitted fields
- reject kitty `Text` sentinel key reports that omit associated text, such as
  `CSI 0u`, while preserving valid pure text reports such as `CSI 0;;229u`
- reject shifted alternate key-code reports without Shift active, and reject
  the `Text` sentinel from shifted/base alternate key-code slots
