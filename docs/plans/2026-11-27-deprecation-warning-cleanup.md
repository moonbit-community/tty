# Deprecation Warning Cleanup

Status: implemented.

## Goal

Make `moon check --deny-warn` clean on the toolchain CI actually installs.
`moon check` went from 0 to 56 warnings with no errors on `moon
0.1.20261126 (ccd306a 2026-11-26)`: 52 `write_bytes` deprecations (E0020,
"Use `write_bytesview` instead"), 2 `Buffer` `size_hint` label deprecations
("Use capacity= instead") and 4 `unused_package` warnings for a stale
`moonbitlang/async` import.

## Context and decisions

These come from a toolchain roll, not from the async bump. `ci.yml` installs
`cli.moonbitlang.com/install/unix.sh` unpinned, so the runner decides which
core the tree is checked against: `moon 0.1.20261102` accepted these calls on
2026-11-04 and `moon 0.1.20261126` deprecates them. Measured, not assumed —
`fix/toolchain-upgrade-warnings` still pins `moonbitlang/async@0.22.4` and
fails `moon check --deny-warn` with the same `[0020]` errors once CI installs
the 2026-11-26 toolchain, so async 0.22.7 is not what deprecated them.

Both deprecations are renames of the same operation, not behaviour changes:

- `@buffer.Buffer::write_bytes(Bytes)` became `write_bytesview(BytesView)`.
  A `Bytes` value coerces to `BytesView`, so every call site keeps passing what
  it already passed; only the method name changes.
- The `size_hint` label of `@buffer.Buffer::new` became `capacity`.

Decisions:

- Take the fix sites from the compiler instead of searching the tree. Each
  diagnostic in `moon check --output-json` carries a `fixes` payload with the
  exact `path`/`loc`/`expect`/`new_text`, so the batch is applied as one
  reviewable edit list and no comment, string literal or unrelated
  `write_bytes` spelling can be hit by accident.
- Fix all 56 sites here rather than suppressing the diagnostics. There is no
  reason to keep a deprecated call once the replacement exists.
- Drop the stale `"moonbitlang/async"` imports instead of keeping them for
  looks. `async fn` is syntax, so a package that only writes `async fn main`
  does not need the package; `examples/color`, `examples/input`,
  `tests/isatty` and `tests/open` were the four such packages.
  `tests/resize` keeps its import because it really calls
  `@async.with_timeout`. No `moon.mod` dependency entry changes: the module is
  still required for `moonbitlang/async/stdio` in those demos.

## Target files

- `command.mbt`, `internal/vt/{clipboard,cursor,sgr}.mbt`,
  `internal/win32/encoder.mbt`: `write_bytes` -> `write_bytesview`.
- `internal/sidecar/protocol.mbt`: `write_bytesview` and `capacity=`.
- `internal/vt/sequence.mbt`: the `bytes_from_buffer` `size_hint` parameter is
  forwarded as `capacity=`; the parameter name itself is unchanged.
- `internal/vt/clipboard_test.mbt`, `internal/win32/encoder_wbtest.mbt`,
  `tests/isatty_test.mbt`: the same rename in test code.
- `examples/{color,input}/moon.pkg`, `tests/{isatty,open}/moon.pkg`: remove the
  unused import.
- `docs/plan.md`, this plan.

No new types, helpers, fields, functions, packages or dependencies. `moon fmt`
reflows one `Command::write_to` arm in `command.mbt`, because
`buf.write_bytesview(@vt.begin_synchronized_update)` no longer fits in 80
columns.

## Public API changes

None. Every changed site is a call on a `@buffer.Buffer` value, inside a
function body. `moon info` regenerates no `.mbti` file: the internal `vt`
helpers and the root `Command` type keep their signatures, and removing a
package import does not appear in a generated interface.

## Invariants

- `write_bytesview` writes the same bytes as `write_bytes` did, so every
  emitted VT sequence, sidecar frame and clipboard payload is byte-identical.
  The byte-equality assertions in the existing tests (`command` batches,
  `internal/vt/clipboard_test`, `internal/win32/encoder_wbtest`) guard this.
- Removing the unused imports changes no runtime behaviour: they named a
  package none of those files referenced.

## Acceptance criteria

- `moon fmt --check` is clean.
- `moon check --deny-warn` is clean for native and wasm, in the root module and
  in every nested module (`examples`, `tests`, `tests/{open,isatty,resize}`).
- `moon test --deny-warn` passes for native and wasm.
- `moon info` leaves the tree unchanged (`git diff --exit-code`).
- No `.mbti` diff, and no change to any emitted byte sequence.

## Validation

Run on macOS arm64 with `moon 0.1.20261126 (ccd306a 2026-11-26)` — the
build CI installs — and `moonbitlang/async@0.22.7`:

- `moon fmt` applied, then `moon fmt --check`: exit 0.
- `moon check --deny-warn` and `moon check --target native --deny-warn`:
  exit 0, 0 warnings (56 before the change).
- The same two commands in `examples`, `tests`, `tests/open`, `tests/isatty`
  and `tests/resize`: exit 0, 0 warnings.
- `moon test --deny-warn`: 213/213 passed (native), 208/208 passed (wasm).
  One native run of the full suite hit
  `tty query dynamic colors coordinates input and output` once
  (`FAILED: expected background color`); the same test passes in isolation
  (3/3) and the next two full native runs were 213/213, so it is the pipe-fed
  color-query test's timing, not these renames — the bytes it matches on are
  unchanged.
- `moon info`: no `.mbti` diff.
- `git diff --check`: clean.

Windows is covered by CI only, as before: the `chore/async-0.22.7` run that
carried this change installed `moon 0.1.20261126` on `windows-latest`,
`macos-latest` and `ubuntu-latest` and passed all three.

## Public API audit

- Reviewed every changed site: all are `@buffer.Buffer` method calls inside
  function bodies, or `moon.pkg` import lists. Nothing is added, removed,
  renamed or made visible in a public interface.
- The `internal/vt` bytes constants and their writing helpers keep their
  signatures, so the generated root and internal interfaces are untouched;
  confirmed by an empty `.mbti` diff after `moon info`.
- `internal/vt/sequence.mbt` keeps its private `size_hint` parameter name, so
  no private helper gained a new shape either.
