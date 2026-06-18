# VT Write Helpers

## Goal

Add destination-passing VT sequence helpers so command batching can encode
multiple terminal operations into one buffer before a single `Tty::write`.

## Accepted Design

- Keep `moonbit-community/tty/internal/vt` as the only owner of VT byte
  encoding.
- Add `write_*` helpers that take `buf : @buffer.Buffer` as their first
  argument and append the requested sequence into that buffer.
- Keep existing `Bytes`-returning helpers with their current names and behavior.
  These helpers may become thin wrappers around the new `write_*` helpers.
- Do not expose `write_*` helpers from the root package; they are internal
  implementation surface for root `Tty`/command batching work.
- Constant byte sequences may continue as `pub let` values. A `write_*` helper is
  only required where avoiding per-command temporary `Bytes` allocation matters.

## Target Files / Surfaces

- `internal/vt/moon.pkg`: import `moonbitlang/core/buffer`.
- `internal/vt/sequence.mbt`: add low-level CSI and decimal write helpers.
- `internal/vt/cursor.mbt`: add cursor `write_*` helpers and keep existing
  `Bytes` helpers.
- `internal/vt/sgr.mbt`: add SGR/color `write_*` helpers and keep existing
  `Bytes` helpers.
- `internal/vt/screen.mbt`: add write helper for kitty keyboard flag push.
- `internal/vt/scroll.mbt`: add write helper for top/bottom margins.
- `internal/vt/*_test.mbt`: verify `write_*` output matches existing byte APIs.

## API / Interface Diff

- Root package `.mbti` should remain unchanged.
- `internal/vt/pkg.generated.mbti` will gain public internal-package functions:
  `write_cursor_*`, `write_sgr*`, `write_set_*`,
  `write_push_keyboard_enhancement_flags`, and
  `write_set_top_bottom_margins`.
- Existing `internal/vt` public `Bytes` helpers remain present and compatible.

## Open Questions

- Future command batching may decide whether all constants need corresponding
  `write_*` helpers for call-site uniformity. This task only adds dynamic
  helpers.

## Next Implementation Step

Add buffer-backed sequence writing primitives, then refactor dynamic cursor,
SGR/color, keyboard flag, and scroll-margin helpers to use them.

## Validation Plan

- `moon fmt`
- `moon test internal/vt`
- `moon check`
- `moon info`
- Review `internal/vt/pkg.generated.mbti` and root `pkg.generated.mbti` diffs.

## Validation Results

- `moon fmt internal/vt`: passed.
- `moon test internal/vt`: passed, 24 tests.
- `moon check`: passed with warnings only from the separate draft
  `command.mbt` file (`write_to` unused, missing explicit core/buffer import,
  unfinished `Tty::execute` placeholder).
- `moon info internal/vt`: passed.
- `git diff --cached --check`: passed.

## Public API Audit

- Root package `pkg.generated.mbti` was intentionally not regenerated because
  the root `command.mbt` draft is incomplete and would pollute the root public
  interface.
- `internal/vt/pkg.generated.mbti` gained only the intended internal-package
  `write_*` helpers plus its `moonbitlang/core/buffer` import.
- Existing `internal/vt` `Bytes` helpers remain present and behavior-compatible.
