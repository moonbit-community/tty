# Agent Queued Input And Shell Commands

## Goal

Extend `examples/agent` with two interactive demo behaviors:

- `Tab` queues the current input and submits it after one second.
- Inputs beginning with `!` execute a shell command and show merged output.

## Design

- Keep the change scoped to `examples/agent`.
- Add `moonbitlang/async/aqueue` and `moonbitlang/async/process` imports to the
  agent example package.
- Introduce a private example-local `AgentEvent` queue so tty input, delayed
  queued input, and shell results are serialized through one render path.
- Run `tty.read_event` in a task-group background task and send decoded terminal
  events into the queue.
- On `Tab`, capture the current editor text, clear the editor, redraw the input
  region, then spawn a one-second delayed task that sends the captured text
  back into the agent queue.
- Treat submitted text whose first character is `!` as a shell command:
  - Unix: `sh -c <command>`
  - Windows: `powershell -NoProfile -Command <command>`
- Store shell-command mode separately from editor text. The `!` marker changes
  the prompt and transcript display but is not part of the editable command
  buffer.
- Use `@process.collect_output_merged` for shell execution.
- Give shell commands an immediate-EOF stdin pipe so they do not consume the
  agent's terminal input.
- Process tasks must not write to the tty directly. They enqueue a shell-result
  event for the main render loop.

## Public API Changes

- None. This is an example-only feature.
- Root `.mbti` should remain unchanged.

## Acceptance

- `Tab` does not block further typing while the queued input waits for one
  second.
- Queued normal input later appears as a transcript turn and fake agent reply.
- Queued shell input later starts shell execution.
- `!cmd` submitted with Enter starts shell execution immediately.
- Shell output is appended through the same transcript rendering path and keeps
  the current editor content visible.
- Composer prompt changes from `> ` to `! ` after the user enters shell mode
  with `!`.
- Pressing Backspace on an empty shell command exits shell mode and restores the
  `> ` prompt.

## Validation

- `moon fmt`
- `moon check examples/agent`
- `moon test examples/agent`
- `moon check`
- `moon test`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Added a private `AgentEvent` queue for `examples/agent`.
- Moved terminal input reading into a background task after the initial cursor
  probe, so it does not race with `Tty::query_cursor_position`.
- Added `Tab` delayed submission by clearing the editor immediately and
  enqueueing the captured text after one second.
- Added `!cmd` shell execution through `@process.collect_output_merged`.
- Changed the composer prompt to `! ` while editing shell command input, without
  storing the leading `!` in editor text.
- Empty shell-command Backspace exits shell mode and restores the `> ` prompt.
- Shell commands receive EOF on stdin instead of sharing the agent tty input.
- Shell worker tasks enqueue results instead of writing to the tty directly.
- Updated the agent status/help text and README example description.

## Public API Audit

- No root package, `input`, `vt`, or `color` public API changed.
- No `.mbti` files changed after `moon info`.
- New types and helpers are private to `examples/agent`.

## Validation Results

- `moon fmt`
- `moon check examples/agent`
- `moon test examples/agent` -> 17 passed
- `moon check`
- `moon test` -> 92 passed
- `moon info`
- generated `.mbti` diff reviewed: no changes
- `git diff --check`
