# Windows Output VT Mode

## Goal

Enable Windows virtual-terminal output processing during scoped raw terminal
sessions so root `Tty` output commands work in Windows consoles while preserving
the previous console state.

## Status

Done.

## Context and Decisions

Windows input raw mode already enables `ENABLE_VIRTUAL_TERMINAL_INPUT`, but the
output side does not enable `ENABLE_VIRTUAL_TERMINAL_PROCESSING`. That leaves VT
output commands dependent on the host console's default mode.

Use the raw-mode lifecycle instead of changing output mode at `Tty::new` time.
Entering raw mode is already the package's explicit stateful terminal session
boundary, and it has an existing restore path through `Tty::leave_raw_mode` and
`Tty::set_state`.

On Windows, capture both input and output console modes in the private `State`
representation. If the output handle is not a console, record that no output
mode was captured and leave output restore as a no-op. Raw-mode derivation
should enable:

- input: existing raw-mode flags plus `ENABLE_VIRTUAL_TERMINAL_INPUT`
- output: `ENABLE_VIRTUAL_TERMINAL_PROCESSING` and
  `DISABLE_NEWLINE_AUTO_RETURN`

Also keep `ENABLE_PROCESSED_OUTPUT` on when enabling VT output because Windows
documents it as required for output control-sequence processing.

## References or Standards

- Microsoft `GetConsoleMode` and `SetConsoleMode`.
- Microsoft console output modes:
  `ENABLE_PROCESSED_OUTPUT`, `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, and
  `DISABLE_NEWLINE_AUTO_RETURN`.
- `crossterm` enables `ENABLE_VIRTUAL_TERMINAL_PROCESSING` on the current output
  handle when checking ANSI support.
- Charmbracelet `ultraviolet` enables
  `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN` during its
  Windows raw terminal setup and restores the saved state.

## Target Files

- `state.mbt`
- `state.c`
- `docs/plan.md`
- `docs/plans/2026-05-27-windows-output-vt-mode.md`

## Public API Changes

None intended.

`State` remains an opaque public type with the same exposed methods. The
internal byte layout may change, but `pkg.generated.mbti` should remain
unchanged after `moon info`.

## Invariants

- `Tty` remains opaque and non-generic.
- Root output command APIs stay VT byte-sequence based and do not grow a
  platform dispatch surface.
- Windows output mode changes happen only inside explicit stateful terminal
  session APIs.
- `Tty::leave_raw_mode` and `Tty::set_state` restore any captured output mode.
- Non-console output handles do not make `Tty::get_state` fail only because
  output mode cannot be captured.

## Acceptance Criteria

- On Windows, `Tty::enter_raw_mode` enables input raw mode, VT input, output VT
  processing, and delayed newline auto-return behavior.
- On Windows, restoring a `State` restores the captured input mode and captured
  output mode when one exists.
- If output mode setup fails after input mode was changed, `Tty::enter_raw_mode`
  attempts to restore the prior input/output state before raising the error.
- Unix behavior is unchanged.
- There is no public `.mbti` API diff.

## Validation Commands

- `moon check` - passed.
- `moon test .` - passed, 19 tests.
- `moon test` - passed, 133 tests.
- `moon fmt` - passed.
- `moon info` - passed.
- Windows manual validation when available:
  - `moon run examples/raw` - not run in this environment.
  - `moon run examples/cursor` - not run in this environment.
  - `moon run examples/input` - not run in this environment.
  - `moon run examples/pager -- README.md` - not run in this environment.

## Public API Audit

No source public API changed. `State` remains opaque and the public method
signatures are unchanged.

`moon info` produced no `pkg.generated.mbti` diff.

## Result Notes

Windows `State` now stores the captured input mode, an optional captured output
mode, and whether that output mode exists. `Tty::get_state` still requires an
input console mode but treats a non-console output handle as "no output mode to
restore."

`State::make_raw` keeps the previous input raw-mode behavior and, when an output
mode was captured, enables `ENABLE_PROCESSED_OUTPUT`,
`ENABLE_VIRTUAL_TERMINAL_PROCESSING`, and `DISABLE_NEWLINE_AUTO_RETURN`.

`Tty::set_state`, `Tty::enter_raw_mode`, and `Tty::leave_raw_mode` now pass both
input and output handles to the private FFI. `Tty::set_state` and
`Tty::enter_raw_mode` attempt to restore the old state if applying the new state
fails after a partial mode change.

## Open Questions

- Non-raw output helpers such as `examples/color` still do not automatically
  enable VT processing unless run inside a raw session. A separate explicit
  output-mode API or crossterm-style lazy output enable can be considered later
  if Windows color output should work outside raw sessions.
