# tty sidecar wire protocol (version 1)

The sidecar is a small native executable that performs terminal syscalls on
behalf of a MoonBit program running on the wasm backend (under `moonrun`),
where no libc surface exists. It is spawned with **stdin/stdout/stderr
inherited** from the parent, so its file descriptors 0/1/2 refer to the same
open file descriptions (and therefore the same terminal) as the parent's
stdio.

On Unix, keyboard and mouse input never crosses this protocol: the parent
reads terminal bytes from its own stdin and decodes them itself. The sidecar
only covers what wasm cannot do — termios control, `isatty`, window size,
and resize notifications (`SIGWINCH` is a signal, which wasm cannot
receive).

On Windows, console input arrives as `INPUT_RECORD`s, which plain byte reads
cannot represent with full fidelity (mouse, focus, resize records). When the
parent enables `WATCH`, the sidecar becomes the console's sole input
consumer: it reads records with `ReadConsoleInputW` and streams them raw
over the event connection; the parent decodes them with its existing Win32
record parser. Resizes then arrive as `WINDOW_BUFFER_SIZE_EVENT` records —
no polling.

All integers are **little-endian**.

## Transport

The parent listens on an ephemeral TCP port on `127.0.0.1` and spawns the
sidecar with:

```
tty-sidecar --port <port>
```

and the environment variable `MOONBIT_TTY_SIDECAR_TOKEN` set to a hex string.
The sidecar opens **two** connections to that port, strictly in this order:

1. the **control** connection — strict request/response,
2. the **event** connection — unsolicited events only (sidecar → parent).

The control handshake completes before the event connection is opened, so
the parent identifies the two connections by accept order and validates each
with its magic.

## Handshake

Immediately after connecting, the sidecar sends on each connection:

| field     | type  | value                                   |
|-----------|-------|-----------------------------------------|
| magic     | u32   | `"MTTC"` (control) / `"MTTE"` (event), i.e. bytes `4D 54 54 43` / `4D 54 54 45` |
| proto     | u16   | 1                                       |
| token_len | u16   | length of token (≤ 256)                  |
| token     | bytes | ASCII copy of `MOONBIT_TTY_SIDECAR_TOKEN` |

The parent validates magic, protocol version and token and closes the
connection on mismatch.

## Frames

Request (parent → sidecar, control connection):

| field  | type | notes                    |
|--------|------|--------------------------|
| op     | u8   | opcode                   |
| req_id | u32  | echoed in the response   |
| len    | u16  | payload length (≤ 4096)  |
| payload| bytes|                          |

Response (sidecar → parent, control connection):

| field  | type | notes                                        |
|--------|------|----------------------------------------------|
| kind   | u8   | 0 = ok, 1 = error                            |
| req_id | u32  | copied from the request                      |
| len    | u16  | payload length                               |
| payload| bytes| op-specific (ok) / `errno i32` (error)       |

Error payloads carry the Unix `errno` (or Windows `GetLastError`) value of
the failing call, matching what `moonbitlang/async/os_error` expects on the
same host OS.

Event (sidecar → parent, event connection):

| field  | type | notes                             |
|--------|------|-----------------------------------|
| kind   | u8   | 2 = event                         |
| req_id | u32  | always 0                          |
| len    | u16  | payload length                    |
| payload| bytes| `event u8` followed by event data |

Defined events:

- `1` RESIZE: `rows i32, cols i32` — Unix only, sent after `SIGWINCH` while
  watching is enabled. The event socket is non-blocking sidecar-side and
  resize is idempotent, so bursts are coalesced: when the parent is not
  draining the connection, intermediate sizes are dropped and one event with
  the latest size is sent once the socket is writable again. A slow parent
  can therefore never stall the sidecar.
- `2` INPUT_RECORDS: a batch of raw Win32 `INPUT_RECORD` structs, 20 bytes
  each — Windows only, streamed while watching is enabled. Records are never
  dropped; when the parent falls behind, the sidecar stops reading the
  console instead (backpressure lands in the console's own input buffer).

Parents skip unknown event codes, so future sidecars can add events without
breaking older parents.

## Terminal slots

Requests never carry parent file descriptors (they are opaque host handles
on wasm). Terminals are addressed by slot:

| slot | meaning                  |
|------|--------------------------|
| 0    | inherited stdin (fd 0)   |
| 1    | inherited stdout (fd 1)  |
| 2    | inherited stderr (fd 2)  |

## Opcodes

| op   | name         | request payload       | ok payload            |
|------|--------------|-----------------------|-----------------------|
| 0x01 | ISATTY       | `which u8`            | `tty u8` (0/1)        |
| 0x02 | ENTER_RAW    | `input u8, output u8` | empty                 |
| 0x03 | LEAVE_RAW    | `input u8, output u8` | empty                 |
| 0x05 | WINSIZE      | `which u8`            | `rows i32, cols i32`  |
| 0x06 | WATCH        | `enable u8`           | empty                 |
| 0x07 | SHUTDOWN     | empty                 | empty, then exit(0)   |

`WATCH` gates terminal-event delivery: resize notifications on Unix,
exclusive console `INPUT_RECORD` streaming on Windows. Parents that never
enable it leave console input untouched.

Terminal state (termios on Unix, console modes on Windows) never crosses the
wire: `ENTER_RAW` captures the current state inside the sidecar (first call
only), derives the raw state exactly like the native `state.c` stub, and
applies it; `LEAVE_RAW` restores the captured state. `ISATTY` and `WINSIZE`
mirror the native `isatty.c` / `size.c` semantics.

## Lifetime and safety

- The sidecar exits when the control connection reaches EOF or errors, when
  the listener cannot be reached at startup, or on `SHUTDOWN`.
- If `ENTER_RAW` changed the terminal and no `LEAVE_RAW` followed, the
  sidecar restores the captured original state on disconnect, so a crashed
  parent does not strand the terminal in raw mode.
- On Unix the parent unlinks the temporary binary right after the handshake;
  the running process keeps its image. On Windows the file stays in the temp
  directory until the OS cleans it.
