# SGR Set Method Names

## Goal

Migrate root `Tty` SGR attribute enable commands from short attribute names to
`set_*` method names while keeping old callers working through deprecated
aliases.

## Status

Done.

## Accepted Design

- Rename the canonical root `Tty` methods:
  - `Tty::bold(Self) -> Unit` becomes `Tty::set_bold(Self) -> Unit`
  - `Tty::italic(Self) -> Unit` becomes `Tty::set_italic(Self) -> Unit`
  - `Tty::underline(Self) -> Unit` becomes `Tty::set_underline(Self) -> Unit`
  - `Tty::reverse(Self) -> Unit` becomes `Tty::set_reverse(Self) -> Unit`
- Keep deprecated aliases for the old method names:
  - `bold`
  - `italic`
  - `underline`
  - `reverse`
- Leave targeted reset methods unchanged:
  - `reset_bold`
  - `reset_italic`
  - `reset_underline`
  - `reset_reverse`
- Leave `internal/vt` byte constants unchanged.
- Keep the package below a style-state, renderer, or rich text API.

## Target Files And Surfaces

- `style.mbt`
- `README.md`
- `tty_test.mbt`
- `examples/color/main.mbt`
- root `pkg.generated.mbti`

## API Interface Diff

- Add canonical root methods:
  - `Tty::set_bold(Self) -> Unit`
  - `Tty::set_italic(Self) -> Unit`
  - `Tty::set_underline(Self) -> Unit`
  - `Tty::set_reverse(Self) -> Unit`
- Keep old root method names as deprecated aliases.
- No `internal/vt/pkg.generated.mbti` changes are expected.

## Open Questions

- None.

## Next Implementation Step

Apply the method rename in `style.mbt`, update local call sites to use
`set_*`, then regenerate generated interfaces with `moon info`.

## Validation Plan

- `moon fmt`
- `moon check`
- `moon test .`
- `moon check examples/color`
- `moon test`
- `moon info`
- review generated `.mbti` diff
- `git diff --check`

## Result

- Renamed the canonical root SGR attribute enable methods to `set_bold`,
  `set_italic`, `set_underline`, and `set_reverse`.
- Kept deprecated aliases for `bold`, `italic`, `underline`, and `reverse`.
- Updated README, root tests, and the color example to call the new canonical
  names.

## Public API Audit

- Root `pkg.generated.mbti` now exposes the `set_*` methods as the canonical
  names and records deprecated aliases for the old names.
- `internal/vt/pkg.generated.mbti` did not change.
- No new public types, mutable fields, style-state model, parser state,
  backend behavior, platform files, or dependencies were introduced.

## Validation Results

- `moon check`
- `moon fmt`
- `moon test .` -> 25 passed
- `moon check examples/color`
- `moon test` -> 166 passed
- `moon info`
- generated `.mbti` diff reviewed
- `git diff --check`
