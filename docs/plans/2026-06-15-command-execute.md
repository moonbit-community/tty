# Command Execute

## Goal

Add a first batch of pure output commands so callers can describe terminal
operations as data and execute a command batch with one serialized terminal
write.

## Accepted Design

- Add a root-package `pub(all) enum Command`.
- Keep command values as inert data. No command writes to the terminal until it
  is passed to `Tty::execute`.
- Keep `Command::write_to(buf)` private to the root package.
- `Tty::execute(commands)` builds one `@buffer.Buffer`, appends each command in
  order, and calls `Tty::write` once. An empty command array is a no-op.
- Only include pure write-only commands in this batch. Exclude terminal query
  operations, `with_*` scope helpers, and mouse composite commands for now.
- Add `Print(StringView)` as the text-output command. It writes the string view
  as UTF-8 into the command batch buffer and does not escape or sanitize
  terminal control bytes embedded in the text.

## Target Files / Surfaces

- `command.mbt`: command enum, private encoder, and `Tty::execute`.
- `moon.pkg`: add `moonbitlang/core/buffer` to normal imports.
- `tty_test.mbt`: black-box tests for command batching and empty batches.
- `pkg.generated.mbti`: generated root public API diff.

## API / Interface Diff

- Root package gains `pub(all) enum Command`.
- Root package gains `pub async fn Tty::execute(Self, Array[Command]) -> Unit`.
- `Command` variants cover cursor movement, screen mode constants,
  erase/cursor-visibility commands, style/color commands, scroll margins,
  synchronized updates, bracketed paste/focus/auto-wrap modes, kitty keyboard
  enhancement push/pop, and `Print(StringView)`.
- This command task should not add further `internal/vt` API. The same PR also
  includes the prior VT write-helper task; its `internal/vt` API diff is tracked
  in `docs/plans/2026-06-15-vt-write-helpers.md`.

## Open Questions

- Mouse enable/disable commands are intentionally deferred because they are
  composite sequences rather than one VT command each.
- Query commands are intentionally deferred because they require coordinating
  writes with input responses.

## Next Implementation Step

Replace the draft `command.mbt` with the accepted command enum and buffer-backed
executor, then add tests that validate batch output order and empty no-op
behavior.

## Validation Plan

- `moon fmt`
- `moon test .`
- `moon check`
- `moon info`
- Review root `pkg.generated.mbti` and `internal/vt/pkg.generated.mbti` diffs.
- `git diff --check`

## Validation Results

- `moon fmt`: passed.
- `moon test .`: passed, 27 tests.
- `moon test`: passed, 172 tests.
- `moon check`: passed.
- `moon info`: passed.
- `git diff --cached --check`: passed.
- `Print(StringView)` addendum:
  - `moon fmt`: passed.
  - `moon test .`: passed, 27 tests.
  - `moon test`: passed, 172 tests.
  - `moon check`: passed.
  - `moon info`: passed.

## Public API Audit

- Root `pkg.generated.mbti` gained only the accepted `pub(all) enum Command`
  and `pub async fn Tty::execute(Self, Array[Command]) -> Unit`.
- The `Print(StringView)` addendum changes only the accepted command enum
  surface.
- Relative to the command task, `internal/vt/pkg.generated.mbti` remained
  unchanged. The PR-level `internal/vt` API additions from the earlier
  destination-passing VT work are audited in
  `docs/plans/2026-06-15-vt-write-helpers.md`.
