# Repository Instructions

## Project Goal

- This repository is a low-level MoonBit terminal package for tty state,
  platform stdio handles, VT byte sequences, and host input decoding.
- Keep the package below full TUI framework level. Do not add screen rendering,
  layout, widget, pane, or terminal-emulator state unless a plan explicitly
  changes that scope.

## Source Of Truth

- `README.md` describes the current user-facing MVP target.
- `docs/architecture.md` records package boundaries, non-goals, and design
  decisions that should survive across conversations.
- `docs/plan.md` is the execution board for the next implementation work.
- `docs/plans/*.md` tracks non-trivial task execution, validation, public API
  audit notes, and unresolved design questions.

## Plan Discipline

- Small mechanical fixes can be done without a task plan.
- Before non-trivial changes to public API, platform behavior, input decoding,
  raw mode semantics, or VT sequence organization, create or update the active
  `docs/plans/*.md` entry.
- An active plan should name the goal, target files, public API changes,
  invariants, acceptance criteria, and validation commands before implementation
  expands beyond the current scope.
- If an approved implementation diverges from the active plan, update the plan
  or discuss the deviation before continuing.
- When a planned task is completed, update the corresponding plan with
  validation results and public API audit notes before committing that task.

## Design Approval Gate

- Before editing repository files, the agent must stop and get explicit user
  approval if the change introduces or reshapes any design surface, even when
  that surface is private or package-local.
- Design surface includes private/public structs, enums, traits, methods,
  helpers, fields, buffers, parser states, transition functions, wrapper types,
  package imports, dependencies, C/FFI stubs, native-stub entries,
  platform-specific files, backend selection, timeout/cancellation semantics,
  raw mode behavior, input decoding, tty opening, fd ownership, and platform
  I/O behavior.
- The approval request must include the problem being solved, the proposed
  shape including new types/helpers/fields/files, why existing code cannot be
  reused, the expected public API diff including whether `.mbti` should remain
  unchanged, and the validation plan.
- Until the user approves that shape, the agent must not call `apply_patch`,
  create files, edit plans, or change code.
- User phrases such as "try it", "see whether it works", or "verify it"
  authorize investigation and throwaway experiments only. If an experiment
  needs repository edits, the agent must ask first or keep it outside the repo.
  These phrases do not authorize repository implementation unless the user
  explicitly says to modify code.

## Architecture Facts

- The root `tonyfettes/tty` package owns tty handles, stdio construction,
  raw-mode state, and platform FFI.
- `tonyfettes/tty/internal/vt` emits VT/ANSI byte sequences for root `Tty`
  methods. It does not own an output stream and does not maintain screen state.
- `tonyfettes/tty/input` decodes host input bytes from an `@io.Reader` into
  input events. It is not a text editor and should not own a line buffer.
- `examples/*` packages are demos and manual validation tools. They can exercise
  APIs, but they are not themselves public library API and should not import
  `tonyfettes/tty/internal/vt` directly.

## Code Readability

- Parser and state-machine code must be written for human review first. Prefer
  direct pattern matching over nested `length()` checks and indexed access when
  the shape being matched is semantic.
- For byte protocols, use rest patterns to express prefix/body/final-byte
  shapes when possible, such as CSI framing with `ESC [` + params + final,
  instead of manually slicing off the last byte.
- Helper names should describe the terminal concept they implement. Avoid
  vague names that only describe implementation details such as "param event"
  when the helper is really parsing a key sequence or applying modifiers.
- Keep defensive checks at clear boundaries. Once a function receives a narrowed
  shape such as a CSI body, do not repeat outer framing checks inside deeper
  helpers.

## Validation

- For MoonBit source changes, run the smallest relevant checks first, then the
  repository-level checks needed for the task:
  - `moon fmt`
  - `moon check`
  - targeted `moon test <package-or-path>` when possible
  - `moon info`
- Review any generated `.mbti` diff after `moon info`. Treat `.mbti` changes as
  public API changes, not formatting churn.
- For demo-only changes under `examples/*`, run `moon check <examples-path>`
  when that command is available and record manual terminal validation if
  behavior depends on a real tty.

## Public API Audit

- Keep parser state, buffers, platform handles, and transition helpers internal
  unless external callers have a concrete use case.
- Prefer opaque exported types over public records when callers do not need
  field access.
- Public mutable fields are not allowed unless the mutability is part of the
  documented contract.
- White-box tests do not justify widening visibility. Prefer package-private
  helpers and `_wbtest.mbt` tests.

## Git Workflow

- Use Conventional Commits, for example `feat(vt): add cursor sequences`.
- Keep commits scoped to one logical task. Do not mix workflow docs with
  unrelated implementation changes unless the docs are the active plan for that
  implementation.
- Do not revert unrelated user changes.
