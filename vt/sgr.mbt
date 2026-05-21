///|
/// Bold or increased intensity (SGR 1), ECMA-48.
pub let bold : Bytes = b"\x1b[1m"

///|
/// Normal intensity (SGR 22), ECMA-48.
pub let reset_bold : Bytes = b"\x1b[22m"

///|
/// Italic (SGR 3), ECMA-48.
pub let italic : Bytes = b"\x1b[3m"

///|
/// Not italic (SGR 23), ECMA-48.
pub let reset_italic : Bytes = b"\x1b[23m"

///|
/// Underline (SGR 4), ECMA-48.
pub let underline : Bytes = b"\x1b[4m"

///|
/// Not underlined (SGR 24), ECMA-48.
pub let reset_underline : Bytes = b"\x1b[24m"

///|
/// Reverse video (SGR 7), ECMA-48.
pub let reverse : Bytes = b"\x1b[7m"

///|
/// Positive image (SGR 27), ECMA-48.
pub let reset_reverse : Bytes = b"\x1b[27m"

///|
/// Construct an SGR sequence with one parameter.
pub fn sgr1(p1 : Int) -> Bytes {
  csi1(p1, b'm')
}

///|
/// Construct an SGR sequence with three parameters.
pub fn sgr3(p1 : Int, p2 : Int, p3 : Int) -> Bytes {
  let len1 = count_decimal_digits(p1)
  let len2 = count_decimal_digits(p2)
  let len3 = count_decimal_digits(p3)
  let buf : FixedArray[Byte] = FixedArray::make(5 + len1 + len2 + len3, 0)
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, p1, offset=2, length=len1)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p2, offset=offset + 1, length=len2)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p3, offset=offset + 1, length=len3)
  buf[offset] = b'm'
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Construct an SGR sequence with five parameters.
pub fn sgr5(p1 : Int, p2 : Int, p3 : Int, p4 : Int, p5 : Int) -> Bytes {
  let len1 = count_decimal_digits(p1)
  let len2 = count_decimal_digits(p2)
  let len3 = count_decimal_digits(p3)
  let len4 = count_decimal_digits(p4)
  let len5 = count_decimal_digits(p5)
  let buf : FixedArray[Byte] = FixedArray::make(
    7 + len1 + len2 + len3 + len4 + len5,
    0,
  )
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, p1, offset=2, length=len1)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p2, offset=offset + 1, length=len2)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p3, offset=offset + 1, length=len3)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p4, offset=offset + 1, length=len4)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, p5, offset=offset + 1, length=len5)
  buf[offset] = b'm'
  buf.unsafe_reinterpret_as_bytes()
}
