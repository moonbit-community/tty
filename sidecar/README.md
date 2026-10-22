# tty sidecar

`sidecar.c` is a small C program that owns the terminal on behalf of a
`moonbit-community/tty` program and relays everything over its stdio pipes.
The protocol part is shared; the rest is one half per platform:

- Unix: opens `/dev/tty`, handles raw mode, size and `SIGWINCH`, forwards
  input as VT bytes.
- Windows: opens `CONIN$`/`CONOUT$`, handles console modes and size,
  forwards input as raw `INPUT_RECORD`s and window size events as resizes.

It restores the terminal when its command pipe closes or it is signalled, so
the terminal is usable again even after the parent was killed.

## How programs get one

`Tty::open()` looks for the sidecar in this order, on every target:

1. The executable named by the `TTY_SIDECAR` environment variable. This is
   an override for tests, development and hosts where the next step is not
   possible.
2. The executable embedded in `internal/sidecar/sidecars.generated.mbt`
   for the running `<os>-<arch>` (`macos-arm64`, `linux-x86_64`, ...),
   written to a temporary directory, started, and deleted again. The
   `sidecars` GitHub workflow rebuilds the binaries whenever this directory
   changes on `main` and commits the regenerated file back.

Build a standalone sidecar with any C compiler:

```sh
cc -O2 -Wall -o sidecar/sidecar sidecar/sidecar.c      # Unix
cl /O2 /Fe:sidecar.exe sidecar\sidecar.c               # Windows
```

## Protocol

Frames are `tag:u8 len:u32le payload`, spoken on the sidecar's stdin
(commands) and stdout (events). The MoonBit side is `internal/sidecar`.

| direction | tag | payload |
|---|---|---|
| parent → sidecar | `0x01 SET_RAW` | `u8`, 1 enters raw mode, 0 leaves it |
| parent → sidecar | `0x02 WRITE` | bytes written to the terminal |
| sidecar → parent | `0x80 HELLO` | `u32` protocol version (1), `u16` rows, `u16` cols |
| sidecar → parent | `0x81 INPUT` | bytes read from the terminal (Unix) |
| sidecar → parent | `0x82 RESIZE` | `u16` rows, `u16` cols |
| sidecar → parent | `0x83 ERROR` | UTF-8 message |
| sidecar → parent | `0x84 RECORD` | one raw `INPUT_RECORD` (Windows) |

The Unix sidecar sends terminal input as `INPUT` frames and the Windows
sidecar as `RECORD` frames; `internal/sidecar` encodes each record into VT
input bytes, so readers see one VT byte stream on every platform. EOF on the
command pipe ends the sidecar.
