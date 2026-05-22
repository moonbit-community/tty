///|
/// Erase in Line (EL), ECMA-48.
///
/// Erases from the cursor to the end of the current line.
pub let erase_line_right : Bytes = b"\x1b[K"

///|
/// Erase in Line (EL), ECMA-48.
///
/// Erases from the start of the current line to the cursor.
pub let erase_line_left : Bytes = b"\x1b[1K"

///|
/// Erase in Line (EL), ECMA-48.
///
/// Erases the entire current line.
pub let erase_line_all : Bytes = b"\x1b[2K"
