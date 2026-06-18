# LaTeX Display Demo And Kitty Graphics API

## Goal

Add a terminal LaTeX display demo that lets the user type a formula, renders it
with external tools, and displays the rendered PNG in Kitty graphics capable
terminals. Move the terminal image transport itself into the root tty API as a
low-level terminal protocol capability.

## Status

Done.

## Context And Decisions

- The root package may grow a Kitty Graphics Protocol surface because image
  transport is terminal protocol work, similar to cursor, color, mouse, and
  kitty keyboard support.
- The root package must not grow LaTeX rendering, external tool discovery, or
  document-conversion APIs. Those stay in `examples/latex`.
- Kitty graphics support detection should be protocol-level where practical, not
  only `$TERM` based. The internal input decoder needs to recognize APC
  `ESC _G... ESC \` replies so root query loops can consume them as terminal
  responses instead of surfacing them as ordinary public input.
- The demo will use `moonbitlang/async/process` to run external renderer tools
  and will call the root Kitty graphics API to display the resulting PNG.

## Accepted Design

- Add internal VT helpers that encode Kitty graphics APC commands.
  - Query: send a tiny direct RGB query image with `a=q`.
  - Display: transmit and display direct PNG bytes with action `T`, format
    `f=100`, medium `t=d`, quiet success `q=1`, and chunk flag `m`.
  - Chunks are base64-encoded and capped to a conservative payload size.
- Add an internal terminal-response event for Kitty graphics replies. The root
  query loop consumes `OK` as support and treats failure/no reply as unsupported.
- Add root `Tty` methods for querying and displaying:
  - `Tty::query_kitty_graphics_support(timeout_ms?) -> Bool`
  - `Tty::display_kitty_png(BytesView, image_id? : Int, columns? : Int, rows? : Int) -> Unit`
- Add a `Command` variant for one-shot display through `Tty::execute`:
  - `DisplayKittyPng(BytesView, KittyGraphicsOptions)`
- Add opaque `KittyGraphicsOptions` with a constructor so command batches can
  carry optional image id and cell-size settings without adding public mutable
  fields.
- Add `examples/latex` as a native executable package.
  - The demo owns the input UI, temporary files, and external process pipeline.
  - The renderer pipeline prefers `tectonic` to produce PDF, falls back to
    `pdflatex` when `tectonic` cannot be started, and uses `pdftocairo` to
    convert the PDF to PNG.
  - `Ctrl-C` exits. Enter renders the current formula. Errors are shown in the
    demo instead of panicking when an external tool is missing or fails.

## Target Files And Surfaces

- `internal/vt/*`: Kitty graphics command encoding and tests.
- `internal/input/*`: APC decoding for Kitty graphics responses and tests.
- `tty.mbt`: root query and display methods.
- `command.mbt`: optional `Command` variant for encoded image output.
- `pkg.generated.mbti`: expected root public API diff.
- `examples/latex/*`: new demo package and focused tests.
- `README.md`: mention the new API and demo.
- `docs/architecture.md`: document the scope boundary.
- `docs/plans/2026-06-18-latex-display-demo.md`: checkpoint and validation
  results.

## Public API Changes

Expected root additions:

- `Command::DisplayKittyPng(BytesView, KittyGraphicsOptions)`
- `KittyGraphicsOptions::new(image_id? : Int, columns? : Int, rows? : Int)`
- `Tty::query_kitty_graphics_support(timeout_ms? : Int) -> Bool`
- `Tty::display_kitty_png(BytesView, image_id? : Int, columns? : Int, rows? : Int) -> Unit`

No LaTeX-specific root API is intended. `moonbit-community/tty/input` public API
should remain unchanged; Kitty graphics replies are internal terminal responses.

## Invariants

- Keep the root package below full TUI/framework level: no layout engine,
  widgets, image decoding, LaTeX rendering, or terminal-emulator state.
- Examples do not import `moonbit-community/tty/internal/vt` directly.
- Terminal response traffic is consumed by root query methods and should not
  leak through public `Tty::read_event`.
- Public APIs use opaque/minimal configuration surfaces and do not expose mutable
  fields.
- Demo temporary files are cleaned up on normal paths where possible.

## Acceptance Criteria

- `moon run examples/latex` opens an alternate-screen formula input demo.
- Enter renders the formula with external tools and displays the PNG through
  root Kitty graphics API when supported.
- Unsupported Kitty graphics or missing renderer tools produce a readable demo
  message.
- `Ctrl-C` is the only exit key.
- `Tty::query_kitty_graphics_support` preserves interleaved user input for later
  `Tty::read_event`.
- Root and internal tests cover encoding, APC response parsing, query behavior,
  and demo command construction helpers.

## Validation Plan

```sh
moon fmt
moon test internal/vt
moon test internal/input
moon test .
moon check examples/latex
moon test examples/latex
moon check
moon test
moon info
git diff --check
```

Manual validation recommended:

```sh
moon run examples/latex
```

## Public API Audit

- Root public API changed only for Kitty graphics transport:
  - `Command::DisplayKittyPng(BytesView, KittyGraphicsOptions)`
  - opaque `KittyGraphicsOptions` plus `KittyGraphicsOptions::new`
  - `Tty::query_kitty_graphics_support`
  - `Tty::display_kitty_png`
- `moonbit-community/tty/input` public API did not change. Kitty graphics APC
  replies are internal stream events only.
- `examples/latex/pkg.generated.mbti` exposes no values, errors, types, type
  aliases, or traits after marking demo helper types private.

## Result Notes

- Added internal Kitty graphics VT encoding for protocol support query and
  chunked direct PNG display.
- Added APC response decoding for Kitty graphics replies, including preservation
  of standalone `Alt+_` after the ESC timeout.
- Added root query and direct PNG display methods and a command-batch variant.
- Added `examples/latex`, a native alternate-screen demo that captures a formula,
  runs external render tools through `moonbitlang/async/process.spawn`, and
  displays the PNG through root Kitty graphics when supported.
- Updated the demo renderer to fall back from missing `tectonic` to `pdflatex`,
  while keeping `pdftocairo` as the PNG conversion step.
- Documentation now records that image transport belongs to root tty protocol
  support while LaTeX rendering remains example-only.
- Validation passed:
  - `moon fmt`
  - `moon test internal/vt` (25 tests)
  - `moon test internal/input` (66 tests)
  - `moon test .` (32 root tests)
  - `moon check examples/latex`
  - `moon test examples/latex` (4 tests)
  - `moon check`
  - `moon test` (193 tests)
  - `moon info`
  - `git diff --check`
- `moon info` reintroduced an unrelated trailing blank line in
  `examples/keyboard/pkg.generated.mbti`; that blank line was removed after
  verifying there was no API/content diff so `git diff --check` could pass.
- Manual tmux smoke passed:
  - command: `moon run examples/latex`
  - first paint fit at 100x30 without wrapping or stair-step line drift
  - sending `x^2` updated the formula and status to `Editing.`
  - pressing Enter in an environment without `tectonic` used the `pdflatex`
    fallback, produced `/tmp/tty-latex-*/formula.png`, and reported
    `Rendered PNG. Terminal graphics are not available.`
  - sending `Ctrl-C` exited and left no tmux session running

## Open Questions

- The exact external renderer availability depends on the host environment. The
  demo should be useful even when it can only report missing `tectonic` or
  `pdftocairo`.
