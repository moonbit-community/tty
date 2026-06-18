///|
const Esc : Byte = b'\x1b'

///|
fn count_decimal_digits(n : Int) -> Int {
  guard n >= 0 else {
    abort(
      "@moonbit-community/tty/internal/vt.count_decimal_digits: n should be greater or equal to 0",
    )
  }
  for len = 1, val = n; val >= 10; val = val / 10, len = len + 1 {

  } nobreak {
    len
  }
}

///|
fn bytes_from_buffer(
  size_hint : Int,
  write : (@buffer.Buffer) -> Unit,
) -> Bytes {
  let buf = @buffer.Buffer::Buffer(size_hint~)
  write(buf)
  buf.to_bytes()
}

///|
fn write_decimal_nonnegative(buf : @buffer.Buffer, n : Int) -> Unit {
  if n >= 10 {
    write_decimal_nonnegative(buf, n / 10)
  }
  buf.write_byte((n % 10 + b'0'.to_int()).to_byte())
}

///|
fn write_decimal(buf : @buffer.Buffer, n : Int) -> Unit {
  guard n >= 0 else {
    abort(
      "@moonbit-community/tty/internal/vt.write_decimal: n should be greater or equal to 0",
    )
  }
  write_decimal_nonnegative(buf, n)
}

///|
fn write_csi1(buf : @buffer.Buffer, n : Int, final_byte : Byte) -> Unit {
  buf.write_byte(Esc)
  buf.write_byte(b'[')
  write_decimal(buf, n)
  buf.write_byte(final_byte)
}

///|
fn csi1(n : Int, final_byte : Byte) -> Bytes {
  let len = count_decimal_digits(n)
  bytes_from_buffer(3 + len, buf => write_csi1(buf, n, final_byte))
}

///|
fn write_csi2(
  buf : @buffer.Buffer,
  n1 : Int,
  n2 : Int,
  final_byte : Byte,
) -> Unit {
  buf.write_byte(Esc)
  buf.write_byte(b'[')
  write_decimal(buf, n1)
  buf.write_byte(b';')
  write_decimal(buf, n2)
  buf.write_byte(final_byte)
}

///|
fn csi2(n1 : Int, n2 : Int, final_byte : Byte) -> Bytes {
  let len1 = count_decimal_digits(n1)
  let len2 = count_decimal_digits(n2)
  bytes_from_buffer(4 + len1 + len2, buf => write_csi2(buf, n1, n2, final_byte))
}

///|
fn write_csi3(
  buf : @buffer.Buffer,
  n1 : Int,
  n2 : Int,
  n3 : Int,
  final_byte : Byte,
) -> Unit {
  buf.write_byte(Esc)
  buf.write_byte(b'[')
  write_decimal(buf, n1)
  buf.write_byte(b';')
  write_decimal(buf, n2)
  buf.write_byte(b';')
  write_decimal(buf, n3)
  buf.write_byte(final_byte)
}

///|
fn write_csi5(
  buf : @buffer.Buffer,
  n1 : Int,
  n2 : Int,
  n3 : Int,
  n4 : Int,
  n5 : Int,
  final_byte : Byte,
) -> Unit {
  buf.write_byte(Esc)
  buf.write_byte(b'[')
  write_decimal(buf, n1)
  buf.write_byte(b';')
  write_decimal(buf, n2)
  buf.write_byte(b';')
  write_decimal(buf, n3)
  buf.write_byte(b';')
  write_decimal(buf, n4)
  buf.write_byte(b';')
  write_decimal(buf, n5)
  buf.write_byte(final_byte)
}
