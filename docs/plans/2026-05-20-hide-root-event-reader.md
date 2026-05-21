# Hide Root EventReader

## Goal

Remove `Input::event_reader` from the root package public API now that root
`Tty` owns coordinated terminal input/output operations.

## Status

Done.

## Context And Decisions

- `tonyfettes/tty/input` remains the low-level package for decoding arbitrary
  `@io.Reader` input into terminal input events.
- Root `Input` is a terminal input handle, not the public event-loop facade.
- Root `Tty` is the preferred API when callers need decoded events from a real
  terminal because it owns one buffered `EventReader` and can also coordinate
  terminal request/response protocols such as CPR.
- Exposing `Input::event_reader` from the root package makes it easy for callers
  to accidentally create a second buffered reader and split terminal responses
  away from normal input decoding.

## Target Files

- `tty.mbt`
- `examples/input/main.mbt`
- `examples/pager/main.mbt`
- `pkg.generated.mbti`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-hide-root-event-reader.md`

## Public API Changes

- Remove root `Input::event_reader` from `tonyfettes/tty`.
- Keep `@input.EventReader` public in `tonyfettes/tty/input` for low-level
  decoder users.
- Keep `Tty::read_input` as the root event-reading API.

Breaking change:

- Root callers using `@tty.stdin.event_reader()` must migrate to
  `@tty.Tty::stdio().read_event()` or import `tonyfettes/tty/input` directly
  when decoding a non-terminal `@io.Reader`.

## Invariants

- `Tty` still shares one buffered reader between `read_event` and terminal
  response side-channel methods.
- `input` parser state and buffer internals remain hidden.
- Examples should not depend on root-private `Input::event_reader`.

## Acceptance Criteria

- Root `pkg.generated.mbti` no longer contains `Input::event_reader` or a root
  method returning `@input.EventReader`.
- `examples/input` and `examples/pager` read events through `Tty::read_input`.
- `tonyfettes/tty/input` still exposes `EventReader` for direct decoder use.

## Validation Commands

```sh
moon fmt
moon test .
moon test input
moon check examples/input
moon check examples/pager
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test .` passed: 15 tests.
- `moon test input` passed: 39 tests.
- `moon check examples/input` passed.
- `moon check examples/pager` passed.
- `moon test` passed: 93 tests.
- `moon check` passed.
- `moon info` passed and regenerated public interfaces.

## Public API Audit

- Root `pkg.generated.mbti` no longer exposes `Input::event_reader`.
- No root public method returns `@input.EventReader`.
- `Tty::read_input` remains the root package event-reading API.
- `tonyfettes/tty/input` still exposes opaque `EventReader`,
  `EventReader::new`, `EventReader::read_event`, and the CPR side-channel
  method for low-level decoder users and root `Tty` implementation.
