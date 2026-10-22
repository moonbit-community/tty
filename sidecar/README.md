# tty sidecar

`sidecar.c` is a small single-threaded program that owns the controlling
terminal on behalf of a `moonbit-community/tty` program that cannot touch it
directly, which today means a wasm program running under `moonrun`. It opens
`/dev/tty`, switches raw mode on and off, reports the window size and
`SIGWINCH`, and restores the terminal when its command pipe closes or it is
signalled.

It talks to the parent over its own stdin and stdout with length-prefixed
frames, `tag:u8 len:u32le payload`:

| direction | tag | payload |
|---|---|---|
| parent → sidecar | `0x01 SET_RAW` | `u8`, 1 enters raw mode, 0 leaves it |
| parent → sidecar | `0x02 WRITE` | bytes written to the terminal |
| sidecar → parent | `0x80 HELLO` | `u32` protocol version, `u16` rows, `u16` cols |
| sidecar → parent | `0x81 INPUT` | bytes read from the terminal |
| sidecar → parent | `0x82 RESIZE` | `u16` rows, `u16` cols |
| sidecar → parent | `0x83 ERROR` | UTF-8 message |

The MoonBit side of the protocol is `internal/sidecar`.

Build it with any C compiler:

```sh
cc -O2 -Wall -o sidecar/sidecar sidecar/sidecar.c
```

At runtime the library finds the executable through the `TTY_SIDECAR`
environment variable, or through binaries embedded with
`scripts/embed_sidecar.py` (see `internal/sidecar/embedded.mbt`).
