# Internal VT Package

## Goal

Move the low-level VT byte-sequence package behind the root package boundary so
callers use `Tty` command methods instead of importing `tonyfettes/tty/vt`
directly.

## Target Files

- `vt/**` -> `internal/vt/**`
- root `moon.pkg`
- root `style.mbt` and any root files importing `vt`
- examples that currently import `tonyfettes/tty/vt`
- `README.md`
- `docs/architecture.md`
- generated `.mbti` files

## Public API Changes

- Remove the public `tonyfettes/tty/vt` package.
- Keep VT sequence construction package-private as `tonyfettes/tty/internal/vt`.
- Add root `Tty` command methods only where needed to replace direct example
  imports, especially cursor helpers that were not already surfaced.
- Root `.mbti` should gain only those intentional `Tty` methods.
- `internal/vt/pkg.generated.mbti` may still expose helpers to packages allowed
  by MoonBit `internal/` import rules, but it is no longer importable by
  downstream modules.

## Invariants

- Root `Tty` remains the public output-command surface.
- `internal/vt` remains pure byte construction: no output stream, no state, no
  platform FFI.
- Examples must not import `tonyfettes/tty/internal/vt`.
- No screen rendering, layout, widget, pane, scrollback, or terminal-emulator
  state is introduced.

## Acceptance Criteria

- `rg "tonyfettes/tty/vt|@tty/vt" --glob '!_build/**' --glob '!tests/_build/**'`
  finds no runtime or documentation references except historical plan text if
  needed.
- Examples compile using root `Tty` methods.
- Public docs describe root `Tty` output commands instead of a public `vt`
  package.
- `moon info` removes `vt/pkg.generated.mbti` from the public package tree and
  updates root `.mbti` with only intended additions.

## Validation

- `moon fmt`
- `moon check`
- targeted `moon test internal/vt`
- `moon test`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Completion Notes

- Moved `vt/` to `internal/vt/` and changed the root package import to
  `tonyfettes/tty/internal/vt`.
- Removed direct `tonyfettes/tty/vt` imports from `examples/input` and
  `examples/pager`; both now use root `Tty` command methods.
- Added `Tty::cursor_back` as the only new root method needed to replace an
  example's direct CUB write.
- Updated README, architecture notes, AGENTS instructions, and the execution
  board to describe VT byte construction as internal implementation detail.

## Public API Audit

- Removed the public `tonyfettes/tty/vt` package from the package tree.
- Root `pkg.generated.mbti` gained only `pub async fn Tty::cursor_back(Self, Int) -> Unit`.
- `internal/vt/pkg.generated.mbti` keeps the same byte-builder surface under
  `tonyfettes/tty/internal/vt`, which is constrained by MoonBit `internal/`
  import rules and is not downstream API.

## Validation Results

- `moon fmt`
- `moon check`
- `moon test internal/vt`
- `moon check examples/input`
- `moon check examples/pager`
- `moon test .`
- `moon test`
- `moon info`
- `git diff --check`
