# Unified Windows input decoding

## Goal and approved design

Use one console record pump only for UTF-16 character transport and resize.
All keyboard, mouse, focus, paste, and terminal response semantics belong to
the common byte decoder. The user approved this boundary and requested a PR.

## Target files and shape

- `internal/win32`: reduce record parsing to character payloads, resize, and
  ignored records; remove native key/mouse/focus event mapping. Reuse ByteQueue,
  retain transport surrogate state, coalesce resize notifications.
- `internal/input`: add private win32-input-mode CSI parsing and migrated key
  mapping. Handle synthetic character envelopes through the same decoder so
  wrapped paste, mouse, focus, and replies retain their semantics.
- `internal/vt/screen.mbt`: own the mode query/enable/disable bytes.
- Root Windows input/state code: negotiate mode 9001 before the first read in
  raw mode, preserve interleaved input, and restore the original mode on state
  restoration/close. State snapshots retain private protocol ownership so nested
  raw sessions do not disable their caller's mode. Synchronous cleanup uses a
  console output FFI write; no asynchronous work is required during cancellation.
- `README.md`, `docs/architecture.md`, `docs/plan.md`, package manifests,
  generated internal interfaces, and focused tests.

## Public API and invariants

- Root and public input interfaces remain unchanged. Internal interfaces shrink
  or change as needed; no parser state is exposed to downstream callers.
- Exactly one consumer of the Windows console input queue.
- No direct native key, mouse, or focus event production.
- Unrecognized mode queries fall back to ordinary VT input.
- Preserve resize during queries and input during mode negotiation.
- Preserve cancellation rollback of partial byte sequences and bounded work per
  console pump iteration; no concurrent ReadFile reader on the console handle.
- Keep user's existing untracked files outside this task.

## Acceptance and validation

- Protocol defaults, malformed/overflow parameters, modifiers, keypad, AltGr,
  repeat/release, surrogate pairs, fragmented and wrapped VT sequences.
- Native transport ignores metadata, emits resize only, and does not lose bytes
  when resize wins the read race or a query is in progress.
- Raw mode negotiation and restoration, including nested scopes and cancellation.
- `moon test internal/input`, `moon test internal/win32`, `moon test .`,
  `moon fmt`, `moon check --deny-warn`, `moon test --deny-warn`, `moon info`,
  `git diff --check`; review generated interface diffs and cross-platform CI.
- Windows console/ConPTY integration smoke where supported by this environment.

## Results and API audit

- Windows: `moon fmt`, `moon check --deny-warn`, targeted input/Win32/root
  tests, and the full workspace suite passed (197/197). The input package has
  78 tests, native transport has 6, and root has 33.
- Linux (WSL, isolated v0.10.15 toolchain): full `moon check --deny-warn`
  passed; root/input/Win32 targeted tests passed (115 at that validation point).
  Full Linux tests hit the pre-existing `moonbit-community/pty@0.2.1`
  `login_tty` implicit-declaration error on Ubuntu 26.04. No dependency changes
  or warning suppressions were added for that unrelated failure.
- Generated interfaces with Linux `moon info`, and regenerated `internal/vt`
  after adding its mode constants. Root, public input, and color interfaces are
  unchanged. This avoids checking in Windows-specific Fd alias spelling drift.
- Internal API audit: removed native record, key, mouse, control-state, and
  coordinate exports from `internal/win32`; its event-reader facade remains.
  Added only the internal mode response and three internal VT constants.
  All win32 sequence fields, parser state, buffers, and native records are private.
- ConPTY smoke: a temporary copy of the input example using `Tty::open` ran
  against the working tree, under an isolated `CreatePseudoConsole` harness.
  Verified Shift+A, resize (32x105), paste, focus, SGR mouse, and Ctrl-C exit.
  Also verified an initial cursor-position query, nested raw scopes, and a
  cancelled raw scope. The host wrapper queried mode 9001 before/after:
  initially disabled remained disabled (`2 -> 2`); initially enabled remained
  enabled (`1 -> 1`). Native console modes were restored (`[503,7] -> [503,7]`).
  This is a headless host/transport smoke, not a physical keyboard/IME test.
- The native 10 ms idle polling interval remains. Pump batches now yield after
  at most 64 records; resize notifications coalesce into one pending slot.
- Normalization reuses the decoder rollback buffer and remembers an exhausted
  preview boundary so partial sequences do not get a second escape timeout.
- Existing Windows key-up suppression and repeat expansion remain intact;
  the protocol parser accepts DWORD control-state flags with overflow checks.
- `git diff --check` passed. Existing untracked user files were left untouched.
