# Root Cursor Position Command

## Goal

Add a root `Tty` helper for absolute cursor positioning so callers do not need
to write `@tty/vt.cursor_position(row, col)` manually for common terminal
output operations.

## Design

- Add `Tty::set_cursor_position(row, col)`.
- Delegate directly to `@vt.cursor_position(row, col)`.
- Keep `@tty/vt.cursor_position` public as the byte-only helper.
- Do not add relative cursor movement helpers in this task.

## Public API Changes

- Add `pub async fn Tty::set_cursor_position(Self, Int, Int) -> Unit`.
- Root `.mbti` should expose only that new method.

## Acceptance

- Root command helper writes the same bytes as `@vt.cursor_position`.
- Examples that were manually writing `@tty/vt.cursor_position(...)` can call
  `Tty::set_cursor_position`.
- `vt` remains byte-only.

## Validation

- `moon fmt`
- `moon test .`
- targeted example checks
- `moon test`
- `moon check`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added `Tty::set_cursor_position(row, col)` in the root package.
- Updated root docs and demos to use the root helper for terminal-owned
  absolute cursor movement.
- Kept `@tty/vt.cursor_position` as the byte-only helper for callers that own a
  raw writer.

## Public API Audit

- Root `.mbti` adds only `pub async fn Tty::set_cursor_position(Self, Int, Int)
  -> Unit`.
- No new public types, fields, parser state, platform handles, or dependencies
  were added.
- `examples/cursor` no longer imports `tonyfettes/tty/vt` after switching to
  the root helper.

## Validation Results

- `moon fmt`
- `moon test .` -> 11 passed
- `moon check examples/cursor`
- `moon check examples/pager`
- `moon check examples/agent`
- `moon test` -> 89 passed
- `moon check`
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
