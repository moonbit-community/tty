# Bad Apple Graphics Demo

## Goal

Add a terminal graphics demo that plays the Bad Apple video through the existing
Kitty graphics and Sixel display APIs. Keep this as an example-only validation
tool and do not expand the root `tty` public API.

## Accepted Design

- Add a new native executable package at `examples/bad_apple`.
- Use `/Users/haoxiang/Downloads/bad-apple.mp4` as the default source video.
- Query terminal graphics support at startup:
  - prefer Kitty graphics when available
  - otherwise use Sixel when available
  - otherwise show a readable unsupported status
- Use external tools through `moonbitlang/async/process.spawn`:
  - `ffmpeg` extracts scaled PNG frames into a temporary directory
  - Kitty mode reads each PNG frame and calls `Tty::display_kitty_png`
  - Sixel mode runs `magick <frame.png> sixel:-` and calls
    `Tty::display_sixel`
- Use a conservative low frame rate for the first version so terminal graphics
  throughput stays practical.
- Use `Ctrl-C` as the only exit path and restore raw mode, cursor visibility,
  alternate screen, and temporary files on exit where possible.
- Do not implement audio playback or audio/video synchronization in this pass.

## Target Files And Surfaces

- `examples/bad_apple/main.mbt`: demo UI, external process pipeline, playback
  loop, cleanup.
- `examples/bad_apple/main_wbtest.mbt`: focused tests for command arguments,
  labels, and exit key handling.
- `examples/bad_apple/moon.pkg`: native executable package imports.
- `README.md`: list the new example.
- `docs/architecture.md`: document the example as a graphics validation tool.
- `docs/plans/2026-06-18-bad-apple-demo.md`: plan and validation notes.

## API And Interface Diff

- No root package public API change is intended.
- `moonbit-community/tty/pkg.generated.mbti` should remain unchanged.
- `examples/bad_apple/pkg.generated.mbti` should expose no public values,
  types, aliases, errors, or traits.

## Open Questions

- The default video path is host-specific. This first version keeps it explicit
  because the requested file exists in `~/Downloads`.
- Sixel conversion may be slower than Kitty display because it converts each
  frame through ImageMagick.

## Result Notes

- Added `examples/bad_apple`, a native terminal graphics demo that plays
  `/Users/haoxiang/Downloads/bad-apple.mp4` through the existing root Kitty
  graphics or Sixel APIs.
- The demo extracts 12 FPS, 512 px wide PNG frames with `ffmpeg`, displays PNG
  frames directly in Kitty mode, and converts frames through
  `magick <frame.png> sixel:-` in Sixel mode.
- Playback runs with a background input task so `Ctrl-C` can stop playback while
  frames are being displayed.
- The first version intentionally does not play audio or synchronize with audio.
- Public API audit: no root package API changes were made, and
  `examples/bad_apple/pkg.generated.mbti` exposes no public values, errors,
  types, aliases, or traits.
- Validation passed:
  - `moon fmt`
  - `moon check examples/bad_apple`
  - `moon test examples/bad_apple` (5 tests)
  - `moon check`
  - `moon test` (205 tests)
  - `moon info`
  - `git diff --check`
- Manual tmux smoke passed:
  - command: `moon run examples/bad_apple`
  - session: `tty-bad-apple-smoke-20260618`, size `100x30`
  - this tmux environment reported `Kitty graphics: off | Sixel: off`, so the
    demo showed the unsupported graphics status without trying to play frames
  - `Ctrl-C` exited the alternate-screen app and left no matching process
    running

## Follow-up Aspect Ratio Correction

- Problem: the first demo sizing can look too tall in real terminals because
  terminal cell pixel ratios vary and the initial placement used up to 24 rows.
- Accepted design:
  - Compress extracted frame height to 85% in the `ffmpeg` filter so both Kitty
    and Sixel paths use slightly flatter source frames.
  - Reduce Kitty placement height from 24 rows to 20 rows.
  - Keep this example-only; no root `tty` API changes.
- Target files/surfaces:
  - `examples/bad_apple/main.mbt`
  - `examples/bad_apple/main_wbtest.mbt`
  - `docs/plans/2026-06-18-bad-apple-demo.md`
- API/interface diff: none.
- Validation plan: run `moon fmt`, `moon check examples/bad_apple`,
  `moon test examples/bad_apple`, `moon check`, `moon test`, `moon info`, and
  `git diff --check`.
- Validation passed:
  - `moon fmt`
  - `moon check examples/bad_apple`
  - `moon test examples/bad_apple` (5 tests)
  - `moon check`
  - `moon test` (205 tests)
  - `moon info`
  - `git diff --check`
  - manual ffmpeg single-frame check produced a `512x326` PNG with the updated
    filter

## Next Implementation Step

Create the `examples/bad_apple` package by adapting the existing external-tool
and terminal-screen patterns from `examples/latex`, then update docs and tests.

## Validation Plan

```sh
moon fmt
moon check examples/bad_apple
moon test examples/bad_apple
moon check
moon test
moon info
git diff --check
moon run examples/bad_apple
```
