///|
/// Enter alternate screen buffer, xterm private mode 1049.
pub let enter_alt_screen : Bytes = b"\x1b[?1049h"

///|
/// Leave alternate screen buffer, xterm private mode 1049.
pub let leave_alt_screen : Bytes = b"\x1b[?1049l"

///|
/// Enable bracketed paste mode, xterm private mode 2004.
pub let enable_bracketed_paste : Bytes = b"\x1b[?2004h"

///|
/// Disable bracketed paste mode, xterm private mode 2004.
pub let disable_bracketed_paste : Bytes = b"\x1b[?2004l"
