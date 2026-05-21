# Terminal Stream Events

## Goal

Refactor `tonyfettes/tty/input` so the public low-level reader can represent
both user input and terminal response traffic from the same byte stream. Use
that stream event model to make cursor-position queries tolerate user input
arriving before the terminal response.

## Status

Done.

## Context And Decisions

- A terminal input stream can interleave user key bytes with responses to
  terminal requests such as Cursor Position Report (`CSI row ; col R`).
- The low-level `EventReader` should be able to decode terminal response
  traffic, not only user input.
- `@input.Event` will become the terminal stream event:
  `Input(InputEvent)` for user input and `CursorPosition(row~, col~)` for CPR.
- The old user-input-only event shape becomes `@input.InputEvent`.
- Root `Tty::read_input` remains a user-input API and returns
  `@input.InputEvent`, skipping unmatched terminal responses.
- `Tty::query_cursor_position` writes `CSI 6 n` inside a single async timeout,
  then reads stream events until it sees `CursorPosition` or that timeout
  expires. Input events read while waiting are stored on `Tty` and returned by
  later `Tty::read_input`.
- `CSI R` without CPR parameters remains F3. `CSI row ; col R` is decoded as a
  cursor position stream event. This follows the response-aware stream model;
  modified F3 ambiguity is accepted for now and can be revisited with extended
  cursor-position requests or a terminal-internal package boundary.

## Target Files

- `input/event.mbt`
- `input/decoder.mbt`
- `input/decoder_test.mbt`
- `input/decoder_wbtest.mbt`
- `input/pkg.generated.mbti`
- `tty.mbt`
- `tty_wbtest.mbt`
- `examples/input/main.mbt`
- `examples/pager/main.mbt`
- `examples/agent/main.mbt`
- `README.md`
- `docs/architecture.md`
- `docs/plan.md`
- `pkg.generated.mbti`

## Public API Changes

- Add public `@input.InputEvent`.
- Change public `@input.Event` to wrap input events and cursor-position stream
  responses.
- Change `@input.EventReader::read_event(esc_timeout_ms?)` to return stream
  `Event`.
- Do not expose a separate timed stream-event read method; root `Tty` uses
  `@async.with_timeout_opt` around the whole request/response operation.
- Remove `@input.EventReader::read_cursor_position_response`; callers can read
  stream `Event` and match `CursorPosition`.
- Change root `Tty::read_input` to return `@input.InputEvent`.

## Invariants

- `EventReader` remains the only low-level byte-to-event decoder.
- Normal root input loops using `Tty::read_input` do not receive CPR responses.
- `Tty::query_cursor_position` does not drop user input that arrives before the
  CPR response.
- Unsupported complete input sequences still become `Input(Unknown(bytes))`.
- `vt` stays byte-only.

## Acceptance Criteria

- `EventReader::read_event` returns `CursorPosition(row~, col~)` for
  `CSI row ; col R`.
- `EventReader::read_event` returns `Input(Key(...))` and
  `Input(Unknown(...))` for user input and unsupported sequences.
- `Tty::query_cursor_position` can return a cursor position when an input event
  arrives before the CPR response.
- Input events observed during a cursor-position query are returned by the next
  `Tty::read_input` call in order.
- A cursor-position query uses a global deadline rather than a per-byte query
  timeout.
- Cancelling a low-level `read_event` while it is reading a partial ESC/CSI/UTF-8
  sequence does not advance the decoder transaction.

## Validation Commands

```sh
moon fmt
moon test input
moon test .
moon check examples/input
moon check examples/pager
moon check examples/agent
moon test
moon check
moon info
```

## Validation Results

- `moon check` passed.
- `moon fmt` passed.
- `moon test input` passed: 39 tests.
- `moon test .` passed: 11 tests.
- `moon check examples/input` passed.
- `moon check examples/pager` passed.
- `moon check examples/agent` passed.
- `moon test` passed: 89 tests.
- `moon info` passed and regenerated public interfaces.
- `git diff --check` passed.

## Public API Audit

- `@input.Event` is now the public low-level terminal stream event:
  `Input(InputEvent)` and `CursorPosition(row~, col~)`.
- `@input.InputEvent` carries the old user-input shape: `Key(KeyEvent)` and
  `Unknown(Bytes)`.
- `@input.EventReader::read_cursor_position_response` was removed because CPR
  is now represented in the stream event model.
- `@input.EventReader::read_event_with_timeout` was removed; the only public
  low-level read API is `read_event(esc_timeout_ms?)`.
- `@input.EventReader::read_event` now rolls back its in-flight decoder window
  if cancellation or another error interrupts a partial event before commit.
- Root `Tty::read_input` returns `@input.InputEvent`, so root callers do not
  receive CPR responses in ordinary input loops.
