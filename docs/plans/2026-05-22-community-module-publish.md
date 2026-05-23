# Community Module Rename And Publish CI

## Goal

Rename the MoonBit module from `tonyfettes/tty` to `moonbit-community/tty` and
add tag-based Mooncakes publish CI following `moonbit-community/pty` while
preserving tty-specific native CI needs.

## Target Files

- `moon.mod`
- all `moon.pkg` imports in the root module, examples, and tests
- nested module manifests under `examples/` and `tests/`
- generated `.mbti` files
- `.github/workflows/ci.yml`
- `.github/workflows/publish.yml`
- README, architecture notes, AGENTS instructions, and execution board

## Public API Changes

- The published module/package prefix changes from `tonyfettes/tty` to
  `moonbit-community/tty`.
- Subpackages keep their relative names: `color`, `input`, and `internal/vt`.
- No MoonBit type, function, enum, or method shape should change.
- Generated `.mbti` package/import names are expected to change only because of
  the module rename.

## CI And Publish Shape

- Keep the current cross-platform CI matrix.
- Keep Windows MSVC setup and `MOON_CC=cl.exe` because this package has native C
  stubs.
- Add a publish workflow based on `moonbit-community/pty`:
  - trigger on pushed tags matching `v*`
  - verify the tag version matches `moon.mod`
  - run `moon check --target native`
  - publish with `MOONCAKES_MOONBIT_COMMUNITY_TOKEN`

## Invariants

- The package stays native-target focused.
- No screen renderer, layout, widget, pane, scrollback, or terminal-emulator
  state is introduced.
- `internal/vt` remains internal and pure byte construction.
- Examples and tests continue to use the package through workspace module
  dependencies, now under `moonbit-community/tty@0.1.0`.

## Acceptance Criteria

- Runtime source, examples, tests, README, architecture, AGENTS, and generated
  interfaces use `moonbit-community/tty` instead of `tonyfettes/tty`.
- Historical `docs/plans/*.md` may keep old package names as task history.
- Publish workflow exists and matches the approved pty-style shape.
- CI keeps tty-specific Windows compiler setup.

## Validation

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- review `.mbti` diff
- `git diff --check`

## Completion Notes

- Renamed the root module to `moonbit-community/tty`.
- Updated examples, tests, root package imports, generated interfaces, README,
  architecture notes, AGENTS instructions, and the execution board to use the
  new module prefix.
- Added Mooncakes publish metadata to `moon.mod` with the current GitHub
  repository URL.
- Added `.github/workflows/publish.yml` using the same tag/version/token shape
  as `moonbit-community/pty`.
- Kept the existing cross-platform CI and its Windows `MOON_CC=cl.exe` setup.

## Public API Audit

- Package paths changed from `tonyfettes/tty...` to
  `moonbit-community/tty...`.
- No public type, function, enum, method, or field signature changed.
- `internal/vt` remains internal under the new module path.

## Validation Results

- `moon fmt`
- `moon check`
- `moon test`
- `moon info`
- `moon check --target native`
- `moon publish --dry-run` packaged the module and passed the extracted-package
  check; the final server request failed with local credentials for `tonyfettes`,
  while CI is configured to use `MOONCAKES_MOONBIT_COMMUNITY_TOKEN`.
- `git diff --check`
