# UTF-8 Input Decoding With Core

## Goal

Use `moonbitlang/core/encoding/utf8` directly from `tonyfettes/tty/input` so
terminal input bytes can produce valid non-ASCII text events without adding a
local `tonyfettes/tty/utf8` package or widening this repository toward a text
or TUI framework.

## Status

Done. The local `tonyfettes/tty/utf8` package plan was dropped after
benchmarking showed core batch decoding is substantially faster.

## Context And Decisions

- `EventReader` remains the public byte-to-event boundary.
- ASCII control bytes and recognized escape sequences keep their existing
  precedence over text decoding.
- Printable ASCII keeps the current event shape:
  `Key(KeyEvent::{ code: Char(ch), text: Some(String::from_char(ch)) })`.
- A complete valid UTF-8 sequence for one Unicode scalar should decode to a
  text-bearing key event.
- If the decoded text contains exactly one `Char`, use
  `KeyCode::Char(ch)` and `text=Some(decoded)`.
- If a future text path needs to emit multiple scalar values as one event, use
  the existing `KeyCode::Text` with `text=Some(decoded)`.
- `Text(String)` or `KeyCode::Text` does not mean Unicode grapheme cluster,
  terminal display cell, cursor movement unit, or IME commit unit.
- `input` reads continuation bytes only when the first byte is a syntactically
  valid UTF-8 lead byte.
- `input` uses a tiny lead-byte length check only to bound reads before calling
  `@utf8.decode`; UTF-8 validation remains delegated to core.
- Invalid or incomplete UTF-8 becomes `Unknown(Bytes)` with the bytes read for
  that attempted text event.
- No Unicode normalization, width calculation, line editing, or grapheme
  segmentation belongs in this task.

## References Or Standards

- `moonbitlang/core/encoding/utf8` is the source of truth for UTF-8 validation
  and conversion to `String`.
- Existing `input` event model from `IN-1`.
- Prior comparison:
  - crossterm decodes keyboard text as scalar `char` events.
  - ultraviolet is grapheme-aware for some paths but does not establish a
    strict streaming grapheme guarantee.

## Target Files

- `input/moon.pkg`
- `input/decoder.mbt`
- `input/decoder_test.mbt`
- `input/pkg.generated.mbti`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-utf8-input-decoding.md`

## Public API Changes

- No new public `tonyfettes/tty/utf8` package.
- Reuse existing `KeyCode::Char`, `KeyCode::Text`, and `KeyEvent::text`.
- `EventReader::read_event` behavior expands to return text-bearing key events
  for valid non-ASCII UTF-8 text.

Consumer story:

- `input` callers can treat `key.text` as decoded terminal text when present.
- Callers that need grapheme clusters, display width, or editing units can
  process `key.text` in a higher-level layer.

## Invariants

- Parser helpers and byte-reading helpers stay internal.
- There is no local UTF-8 public API or decoder state type.
- Existing ESC timeout semantics do not change.
- Existing ASCII and escape sequence behavior does not change.
- Valid UTF-8 is decoded at scalar boundaries, not grapheme boundaries.
- `cmd/input` can display the existing event shape without API changes.

## Acceptance Criteria

- No `utf8/` package remains in the repository.
- Valid 2-byte, 3-byte, and 4-byte UTF-8 sequences decode to text-bearing
  `KeyEvent`s.
- Split UTF-8 sequences can complete when continuation bytes arrive within the
  existing timeout path.
- Invalid lead bytes and invalid/incomplete sequences become `Unknown(Bytes)`.
- A non-continuation byte after a valid lead byte is left buffered for the next
  event.

## Validation Commands

```sh
moon fmt
moon check
moon test input
moon info
```

No manual terminal validation is required for this core decode policy change.

## Validation Results

- `moon fmt` passed.
- `moon check` passed.
- `moon test input` passed: 17 tests passed.
- `moon info` passed.

## Public API Audit

- `input/pkg.generated.mbti` did not change after `moon info`.
- No new public types were exposed.
- The existing event API remains the only public surface.
- No raw UTF-8 decoder state or helper leaked.

## Open Questions

- Whether `cmd/input` should append non-ASCII text to the visible buffer during
  integration or only display decoded event status.
