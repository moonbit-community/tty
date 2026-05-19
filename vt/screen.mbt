///|
/// Enter alternate screen buffer, xterm private mode 1049.
pub let enter_alt_screen : Bytes = b"\x1b[?1049h"

///|
/// Leave alternate screen buffer, xterm private mode 1049.
pub let leave_alt_screen : Bytes = b"\x1b[?1049l"
