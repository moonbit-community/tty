# tonyfettes/tty

Tty manipulation module

## MVP

Codex-like TUI

```
+--------------+
| scrollback   | <- Goes into the scrollback of the primary screen of a terminal
+--------------+
| input buffer | <- Support Shift+Enter/Ctrl+J for multi-line input, tab for input queueing
+--------------+
```
