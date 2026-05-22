///|
const Esc : Byte = b'\x1b'

///|
fn count_decimal_digits(n : Int) -> Int {
  guard n >= 0 else {
    abort(
      "@tonyfettes/tty/internal/vt.count_decimal_digits: n should be greater or equal to 0",
    )
  }
  for len = 1, val = n; val >= 10; val = val / 10, len = len + 1 {

  } nobreak {
    len
  }
}

///|
fn write_decimal_digits(
  buf : FixedArray[Byte],
  n : Int,
  offset? : Int = 0,
  length? : Int = count_decimal_digits(n),
) -> Int {
  let mut value = n
  for i in 0..<length {
    let index = offset + length - i - 1
    buf[index] = (value % 10 + b'0'.to_int()).to_byte()
    value = value / 10
  }
  offset + length
}

///|
fn csi1(n : Int, final_byte : Byte) -> Bytes {
  let len = count_decimal_digits(n)
  let buf : FixedArray[Byte] = FixedArray::make(3 + len, 0)
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, n, offset=2, length=len)
  buf[offset] = final_byte
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn csi2(n1 : Int, n2 : Int, final_byte : Byte) -> Bytes {
  let len1 = count_decimal_digits(n1)
  let len2 = count_decimal_digits(n2)
  let buf : FixedArray[Byte] = FixedArray::make(4 + len1 + len2, 0)
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal_digits(buf, n1, offset=2, length=len1)
  buf[offset] = b';'
  let offset = write_decimal_digits(buf, n2, offset=offset + 1, length=len2)
  buf[offset] = final_byte
  buf.unsafe_reinterpret_as_bytes()
}
