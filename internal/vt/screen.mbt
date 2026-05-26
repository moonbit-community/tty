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

///|
/// Query kitty keyboard protocol progressive enhancement flags.
pub let query_keyboard_enhancement_flags : Bytes = b"\x1b[?u"

///|
/// Primary Device Attributes (DA1) request.
pub let request_primary_device_attributes : Bytes = b"\x1b[c"

///|
/// Enable normal mouse tracking, xterm private mode 1000.
pub let enable_mouse_click : Bytes = b"\x1b[?1000h"

///|
/// Disable normal mouse tracking, xterm private mode 1000.
pub let disable_mouse_click : Bytes = b"\x1b[?1000l"

///|
/// Enable button-event mouse tracking, xterm private mode 1002.
pub let enable_mouse_drag : Bytes = b"\x1b[?1002h"

///|
/// Disable button-event mouse tracking, xterm private mode 1002.
pub let disable_mouse_drag : Bytes = b"\x1b[?1002l"

///|
/// Enable any-event mouse tracking, xterm private mode 1003.
pub let enable_mouse_motion : Bytes = b"\x1b[?1003h"

///|
/// Disable any-event mouse tracking, xterm private mode 1003.
pub let disable_mouse_motion : Bytes = b"\x1b[?1003l"

///|
/// Enable SGR extended mouse coordinates, xterm private mode 1006.
pub let enable_sgr_mouse : Bytes = b"\x1b[?1006h"

///|
/// Disable SGR extended mouse coordinates, xterm private mode 1006.
pub let disable_sgr_mouse : Bytes = b"\x1b[?1006l"
