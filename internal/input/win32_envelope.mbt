///|
// ConPTY may wrap VT traffic in character-only win32-input-mode records.
// Normalize these envelopes in the existing rollback buffer before parsing
// VT framing. Real key records (with a virtual key or scan code) stay intact.
async fn EventReader::read_byte(self : EventReader) -> Byte {
  for ;; {
    let start = self.read
    let mut completed = false
    defer (if !completed { self.read = start })
    let byte = self.read_wire_byte()
    if byte != Esc {
      completed = true
      return byte
    }
    let after_escape = self.read
    let normalized = @async.with_timeout_opt(self.esc_timeout_ms, () => {
      self.unwrap_win32_character(start) catch {
        @io.ReaderClosed => None
        error => raise error
      }
    })
    if normalized is Some(Some(bytes)) {
      self.replace_win32_envelope(start, bytes)
      // Return normalized bytes without interpreting an embedded ESC as
      // another envelope here. The next read handles the next wire envelope.
      if bytes.length() > 0 {
        let result = self.read_wire_byte()
        completed = true
        return result
      }
    } else {
      if normalized is None || self.read == after_escape {
        self.timeout_boundary = Some(self.read)
      }
      self.read = after_escape
      completed = true
      return Esc
    }
    completed = true
  }
}

///|
async fn EventReader::read_win32_envelope(
  self : EventReader,
  start : Int32,
) -> Win32Key? {
  guard self.read_wire_byte() == b'[' else { return None }
  // Six bounded decimal fields fit comfortably in this limit.
  for _ in 0..<48 {
    let byte = self.read_wire_byte()
    match byte {
      b'0'..<=b'9' | b';' => ()
      b'_' => {
        let wire = self.data.unsafe_reinterpret_as_bytes()[start:self.read]
        guard wire is [Esc, b'[', .. params, b'_'] else { return None }
        return parse_win32_key(params)
      }
      _ => return None
    }
  }
  None
}

///|
async fn EventReader::unwrap_win32_character(
  self : EventReader,
  start : Int32,
) -> Bytes? {
  guard self.read_win32_envelope(start) is Some(record) &&
    (
      self.in_paste ||
      (record.virtual_key_code == 0 && record.virtual_scan_code == 0)
    ) else {
    return None
  }
  if record.key_down == 0 {
    return Some(b"")
  }
  let mut code = record.unicode_char
  if is_high_surrogate(code) {
    // Do not mutate the buffer until the entire surrogate pair is present.
    // Cancellation can therefore replay the original wire bytes.
    let mut low : Int32? = None
    for _ in 0..<4 {
      let next_start = self.read
      guard self.read_wire_byte() == Esc &&
        self.read_win32_envelope(next_start) is Some(next) &&
        (
          self.in_paste ||
          (next.virtual_key_code == 0 && next.virtual_scan_code == 0)
        ) else {
        return None
      }
      if next.key_down == 0 {
        continue
      }
      guard next.repeat_count == record.repeat_count &&
        is_low_surrogate(next.unicode_char) else {
        return None
      }
      low = Some(next.unicode_char)
      break
    }
    guard low is Some(low) else { return None }
    code = 0x10000 + (code - 0xd800) * 0x400 + low - 0xdc00
  } else if is_low_surrogate(code) {
    return None
  }
  let bytes = Buffer()
  for _ in 0..<record.repeat_count.max(1) {
    bytes.write_char_utf8(codepoint_to_char(code))
  }
  Some(bytes.to_bytes())
}

///|
fn EventReader::replace_win32_envelope(
  self : EventReader,
  start : Int32,
  bytes : Bytes,
) -> Unit {
  let suffix = self.data.unsafe_reinterpret_as_bytes()[self.read:self.tail].to_owned()
  let new_tail = start + bytes.length() + suffix.length()
  self.ensure_capacity((new_tail - self.tail).max(0))
  for i, byte in bytes {
    self.data[start + i] = byte
  }
  for i, byte in suffix {
    self.data[start + bytes.length() + i] = byte
  }
  self.tail = new_tail
  self.read = start
}

///|
async fn EventReader::read_byte_timeout(
  self : EventReader,
  timeout : Int32,
) -> Byte? {
  // A timed-out envelope preview has already waited for this boundary.
  // Replaying its buffered prefix must not start a second timeout.
  if self.timeout_boundary is Some(boundary) && self.read == boundary {
    return None
  }
  let start = self.read
  guard @async.with_timeout_opt(timeout, () => self.read_wire_byte()) is Some(_) else {
    return None
  }
  self.read = start
  Some(self.read_byte())
}
