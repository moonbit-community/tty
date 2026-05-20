# VT Package Cleanup

## Goal

Remove the obsolete `vt/color` compatibility package and inline
`vt/internal/seq` into the main `vt` package.

## Status

Done.

## Context And Decisions

- `tonyfettes/tty/color` is now the semantic color package.
- `tonyfettes/tty/vt/color` is no longer used by repository code and should not
  remain as a compatibility shim.
- The shared CSI/SGR builder package is small and only used by `vt`, so keeping
  it under `vt/internal/seq` adds package surface without a real boundary.
- `csi1` and `csi2` should become private `vt` helpers.
- `sgr1`, `sgr3`, and `sgr5` remain public low-level `vt` protocol helpers.

## Target Files

- `vt/moon.pkg`
- `vt/cursor.mbt`
- `vt/scroll.mbt`
- `vt/sequence.mbt`
- `vt/sequence_wbtest.mbt`
- `vt/sgr.mbt`
- `vt/pkg.generated.mbti`
- `vt/color/*`
- `vt/internal/seq/*`
- `docs/architecture.md`
- `docs/plan.md`
- `docs/plans/2026-05-20-color-output-api.md`
- `docs/plans/2026-05-20-vt-package-cleanup.md`

## Public API Changes

- Remove package `tonyfettes/tty/vt/color`.
- Remove package `tonyfettes/tty/vt/internal/seq`.
- Keep `tonyfettes/tty/vt.sgr1`, `sgr3`, and `sgr5`.
- Keep `tonyfettes/tty/color` unchanged.

## Invariants

- `vt` remains byte-only and does not import root `tty` or write to streams.
- `color` remains the only semantic color package.
- No command-style API is added in this cleanup.

## Acceptance Criteria

- Repository code has no imports of `tonyfettes/tty/vt/color`.
- Repository code has no imports of `tonyfettes/tty/vt/internal/seq`.
- `vt` tests still cover CSI-derived cursor/scroll helpers and public SGR
  helpers.
- `color` tests still pass.

## Validation Commands

```sh
moon fmt
moon test vt
moon test color
moon check cmd/color
moon check cmd/agent
moon test
moon check
moon info
```

## Validation Results

- `moon fmt` passed.
- `moon test vt` passed: 11 tests.
- `moon test color` passed: 6 tests.
- `moon check cmd/color` passed.
- `moon check cmd/agent` passed.
- `moon test` passed: 90 tests.
- `moon check` passed.
- `moon info` passed.

## Public API Audit

- Removed package `tonyfettes/tty/vt/color`.
- Removed package `tonyfettes/tty/vt/internal/seq`.
- Kept `tonyfettes/tty/vt.sgr1`, `sgr3`, and `sgr5` public.
- Moved CSI byte helpers into `tonyfettes/tty/vt` as private implementation
  helpers.
- Kept `tonyfettes/tty/color` unchanged as the semantic color package.
