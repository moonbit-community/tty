# Examples Workspace Split

## Goal

Move demo/manual-validation packages from `cmd/` to a separate `examples`
MoonBit module and add a root `moon.work` that checks both the library module
and examples module together.

## Status

Done.

## Context And Decisions

- Demo packages are not public library API and should not live in the root
  module's package namespace.
- `moon.mod` DSL does not support local path dependencies; workspace membership
  is the intended local-module linkage.
- `examples/moon.mod` depends on `tonyfettes/tty@0.1.0`; `moon.work` members
  make that dependency resolve to the repository root during local checks.
- The root module should keep only dependencies needed by the library itself.

## Target Files

- `moon.work`
- `moon.mod`
- `examples/moon.mod`
- `examples/*`
- `AGENTS.md`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-examples-workspace.md`

## Public API Changes

None. This moves demo packages out of the root module but does not change
library package interfaces.

## Invariants

- Root package APIs and generated `.mbti` files remain unchanged except for
  generated metadata if required by `moon info`.
- `examples/*` packages remain executable demo packages.
- `moon check` from the repository root checks both `.` and `./examples`.
- `moon run examples/<name>` works for former `cmd/<name>` demos.

## Acceptance Criteria

- No `cmd/` directory remains.
- `examples/moon.mod` owns example-only dependencies such as grapheme and
  unicode width.
- Root `moon.mod` no longer declares dependencies used only by examples.
- Existing examples compile in the workspace.

## Validation Commands

```sh
moon fmt
moon check
moon test
moon info
moon check examples/input
moon check examples/pager
moon check examples/agent
moon check examples/color
moon test examples/input
moon test examples/pager
moon test examples/agent
```

## Validation Results

- `moon fmt` passed.
- `moon check` passed and checked both workspace members.
- `moon test` passed: 86 tests.
- `moon info` passed.
- `moon check examples/input` passed.
- `moon check examples/pager` passed.
- `moon check examples/agent` passed.
- `moon check examples/color` passed.
- `moon test examples/input` passed: 5 tests.
- `moon test examples/pager` passed: 6 tests.
- `moon test examples/agent` passed: 11 tests.

## Public API Audit

- No root library `.mbti` files changed.
- Example package `.mbti` files now use package names under
  `tonyfettes/tty/examples/*`.
- Root module dependencies were narrowed to the library dependency on
  `moonbitlang/async`.
- Example-only dependencies moved to `examples/moon.mod`.
