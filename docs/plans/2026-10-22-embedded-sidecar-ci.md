# CI coverage for the embedded sidecars

Status: implemented.

## Goal

Run the pty tests in `tests/` against the sidecar executables embedded in
`internal/sidecar/sidecars.generated.mbt`, on every platform they are built
for: `linux-x86_64`, `linux-arm64`, `macos-arm64`, `macos-x86_64` and
`windows-x86_64`.

## Problem

`Tty::open()` uses the embedded executable for the host unless
`TTY_SIDECAR` names another one. The pty tests always set `TTY_SIDECAR` to
a sidecar compiled from `sidecar/sidecar.c` on the spot, and the regular CI
has no ARM Linux or Intel macOS runner. The only CI path that reached the
embedded table was the root `Tty::open()` test on console-less runners,
which fails fast without a terminal. A Windows-only reap race in 0.6.0 got
through that way.

## Shape

- `tests/isatty_test.mbt`: a private `embedded_sidecar()` switch, on when
  `TTY_TEST_SIDECAR=embedded`. With it on, `runner_args` passes the
  environment through without injecting `TTY_SIDECAR`, and fails if one is
  inherited (it would silently replace the embedded executable);
  `build_sidecar` does nothing. The default stays a sidecar built from
  source, because a change to `sidecar/sidecar.c` is embedded only after it
  reaches `main` and the `sidecars` workflow regenerates the table.
- The switch is a test-only variable rather than a value of `TTY_SIDECAR`,
  so the library's contract (`TTY_SIDECAR` set and non-empty overrides,
  otherwise embedded) stays unchanged.
- `.github/workflows/embedded-sidecars.yml`: one job per embedded
  `<os>-<arch>` (`ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`
  twice, `windows-latest`). It checks the runner's platform is the one the
  job is named for, then runs `moon test tests --deny-warn`
  with `TTY_TEST_SIDECAR=embedded`, which drives both the native and the
  wasm runners. Triggers: `workflow_dispatch`, pushes to `main` and pull
  requests touching `internal/sidecar/**`, `tests/**` or the workflow. The
  `sidecars` workflow pushes the regenerated table with a deploy key, so
  its bot commit triggers this workflow.

- `macos-x86_64` runs on arm64 macOS: the MoonBit installer rejects
  `Darwin x86_64` (first attempt on `macos-15-intel` failed with
  `Unsupported platform`), so no Intel runner can build the tests. The job
  puts a `uname` in front of `PATH` that answers `-m` with `x86_64`, so
  `platform_key` selects the embedded `macos-x86_64` executable, and Rosetta
  runs it. This covers the x86_64 binary, not an Intel host.

## Public API diff

None. `tests/pkg.generated.mbti` and every other `.mbti` stay unchanged.

## Acceptance

- Default `moon test tests` still builds and uses a sidecar from source.
- `TTY_TEST_SIDECAR=embedded moon test tests` passes with no sidecar built
  locally, and fails if `TTY_SIDECAR` is set too.
- The workflow passes on all five platforms.

## Validation

- `moon fmt`, `moon check --deny-warn` (native and wasm), `moon info`,
  `git diff --check`.
- macOS arm64: `moon test tests` 5/5; `TTY_TEST_SIDECAR=embedded moon test
  tests` with `tests/_build/sidecar` removed 5/5, nothing rebuilt; with
  `TTY_SIDECAR=/nope` added, the guard fails the test.
- macOS arm64 with the `uname` shim: 5/5, and the sidecars spawned during
  the run were `Mach-O 64-bit executable x86_64`.
- CI: see the pull request's `embedded sidecars` run.
