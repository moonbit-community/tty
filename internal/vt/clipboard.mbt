///|
/// Set the system clipboard, xterm OSC 52 with the `c` selection.
///
/// The payload is the base64 encoding of the UTF-8 text. An empty text gives an
/// empty payload, which clears the clipboard.
pub fn write_set_clipboard(buf : @buffer.Buffer, text : StringView) -> Unit {
  buf.write_bytes(b"\x1b]52;c;")
  buf.write_string_utf8(@base64.encode(@utf8.encode(text)))
  buf.write_bytes(b"\x1b\\")
}

///|
/// Set the system clipboard, xterm OSC 52 with the `c` selection.
pub fn set_clipboard(text : StringView) -> Bytes {
  bytes_from_buffer(16 + 2 * text.length(), buf => {
    write_set_clipboard(buf, text)
  })
}
