# Root VT Command Methods

## Goal

Add root `Tty` methods for the VT commands currently used directly by
`examples/agent`, so the demo can treat `Tty` as the terminal command surface
while `tonyfettes/tty/vt` remains the byte-sequence layer.

## Design

- Add `Tty` methods named after the underlying VT helpers:
  - `cursor_up`
  - `cursor_forward`
  - `erase_line_all`
  - `set_top_bottom_margins`
  - `reset_top_bottom_margins`
  - `reverse_index`
- Delegate directly to the existing `@vt` byte helpers.
- Keep existing `@tty/vt` APIs public and byte-only.
- Do not add new types, dependencies, parser states, or platform backends.
- Keep demo-local guards for zero relative cursor movement in `examples/agent`.

## Public API Changes

- Add `pub async fn Tty::cursor_up(Self, Int) -> Unit`.
- Add `pub async fn Tty::cursor_forward(Self, Int) -> Unit`.
- Add `pub async fn Tty::erase_line_all(Self) -> Unit`.
- Add `pub async fn Tty::set_top_bottom_margins(Self, Int, Int) -> Unit`.
- Add `pub async fn Tty::reset_top_bottom_margins(Self) -> Unit`.
- Add `pub async fn Tty::reverse_index(Self) -> Unit`.

## Acceptance

- Root methods emit the same bytes as the corresponding `@tty/vt` helpers.
- `examples/agent` no longer imports `tonyfettes/tty/vt`.
- `vt` remains output-stream agnostic.

## Validation

- `moon fmt`
- `moon test .`
- `moon check examples/agent`
- `moon test examples/agent`
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added root `Tty` methods for cursor-up, cursor-forward, erase-entire-line,
  DECSTBM set/reset, and RI.
- Updated `examples/agent` to call root `Tty` methods instead of importing
  `tonyfettes/tty/vt`.
- Kept `tonyfettes/tty/vt` as the byte-only sequence package.

## Public API Audit

- Root `.mbti` adds only the six intended async `Tty` command methods.
- No new public types, public fields, parser state, platform handles,
  dependencies, or backend selection behavior were added.
- `examples/agent` keeps its local zero-count guards for relative cursor
  movement, while root methods delegate to the VT helper semantics.

## Validation Results

- `moon fmt`
- `moon test .` -> 11 passed
- `moon check examples/agent`
- `moon test examples/agent` -> 17 passed
- `moon test` -> 92 passed
- `moon check`
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
