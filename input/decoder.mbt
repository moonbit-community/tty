///|
const Esc : Byte = b'\x1b'

///|
pub async fn[R : @io.Reader] read_event(
  reader : R,
  esc_timeout? : Int = 50,
) -> Event {
  let byte = read_byte(reader)
  if byte == Esc {
    let buffer = @buffer.new()
    buffer.write_byte(Esc)
    read_escape(reader, buffer, esc_timeout)
  } else {
    byte_event(byte)
  }
}

///|
async fn[R : @io.Reader] read_byte(reader : R) -> Byte {
  reader.read_exactly(1)[0]
}

///|
async fn[R : @io.Reader] read_byte_timeout(reader : R, timeout~ : Int) -> Byte? {
  @async.with_timeout_opt(timeout, () => read_byte(reader))
}

///|
async fn[R : @io.Reader] read_escape(
  reader : R,
  buffer : @buffer.Buffer,
  esc_timeout : Int,
) -> Event {
  guard read_byte_timeout(reader, timeout=esc_timeout) is Some(byte) else {
    Key(KeyEvent::new(Escape))
  }
  buffer.write_byte(byte)
  match byte {
    b'[' => read_csi(reader, buffer, esc_timeout~)
    Esc => Key(KeyEvent::new(Escape))
    0x20..<0x7f as byte =>
      Key(
        KeyEvent::new(
          Char(byte.to_char()),
          modifiers=KeyModifiers::new(alt=true),
        ),
      )
    byte => Unknown([Esc, byte])
  }
}

///|
async fn[R : @io.Reader] read_csi(
  reader : R,
  buffer : @buffer.Buffer,
  esc_timeout~ : Int,
) -> Event {
  let mut seen_intermediate = false
  for ;; {
    guard read_byte_timeout(reader, timeout=esc_timeout) is Some(byte) else {
      return Unknown(buffer.to_bytes())
    }
    buffer.write_byte(byte)
    match byte {
      0x30..<0x40 if seen_intermediate => break Unknown(buffer.to_bytes())
      0x30..<0x40 => ()
      0x20..<0x30 => seen_intermediate = true
      0x40..<0x7f => break csi_event(buffer.to_bytes())
      _ => break Unknown(buffer.to_bytes())
    }
  }
}

///|
fn csi_event(csi : Bytes) -> Event {
  match csi {
    [Esc, b'[', b'A'] => Key(KeyEvent::new(Up))
    [Esc, b'[', b'B'] => Key(KeyEvent::new(Down))
    [Esc, b'[', b'C'] => Key(KeyEvent::new(Right))
    [Esc, b'[', b'D'] => Key(KeyEvent::new(Left))
    [Esc, b'[', b'H'] => Key(KeyEvent::new(Home))
    [Esc, b'[', b'F'] => Key(KeyEvent::new(End))
    [Esc, b'[', b'Z'] =>
      Key(KeyEvent::new(Tab, modifiers=KeyModifiers::new(shift=true)))
    [Esc, b'[', b'2', b'~'] => Key(KeyEvent::new(Insert))
    [Esc, b'[', b'3', b'~'] => Key(KeyEvent::new(Delete))
    [Esc, b'[', b'5', b'~'] => Key(KeyEvent::new(PageUp))
    [Esc, b'[', b'6', b'~'] => Key(KeyEvent::new(PageDown))
    _ => Unknown(csi)
  }
}

///|
fn byte_event(byte : Byte) -> Event {
  match byte {
    b'\r' => Key(KeyEvent::new(Enter))
    b'\n' =>
      Key(KeyEvent::new(Char('j'), modifiers=KeyModifiers::new(ctrl=true)))
    b'\t' => Key(KeyEvent::new(Tab))
    b'\x7f' | b'\x08' => Key(KeyEvent::new(Backspace))
    b'\x00' =>
      Key(KeyEvent::new(Char(' '), modifiers=KeyModifiers::new(ctrl=true)))
    0x01..=0x1a =>
      Key(
        KeyEvent::new(
          Char((byte.to_int() - 1 + 'a'.to_int()).unsafe_to_char()),
          modifiers=KeyModifiers::new(ctrl=true),
        ),
      )
    0x1c..=0x1f =>
      Key(
        KeyEvent::new(
          Char((byte.to_int() - 0x1c + '4'.to_int()).unsafe_to_char()),
          modifiers=KeyModifiers::new(ctrl=true),
        ),
      )
    0x20..<0x7f => {
      let char = byte.to_char()
      Key(KeyEvent::new(Char(char), text=[char]))
    }
    _ => Unknown([byte])
  }
}
