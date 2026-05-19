///|
const Esc : Byte = b'\x1b'

///|
fn decimal_len(n : Int) -> Int {
  let mut value = n
  let mut len = 1
  while value >= 10 {
    value = value / 10
    len += 1
  }
  len
}

///|
fn write_decimal(buf : FixedArray[Byte], offset : Int, n : Int) -> Int {
  let len = decimal_len(n)
  let mut value = n
  for i in 0..<len {
    let index = offset + len - i - 1
    buf[index] = (value % 10 + b'0'.to_int()).to_byte()
    value = value / 10
  }
  offset + len
}

///|
fn csi1(n : Int, final_byte : Byte) -> Bytes {
  let len = decimal_len(n)
  let buf : FixedArray[Byte] = FixedArray::make(3 + len, 0)
  buf[0] = Esc
  buf[1] = b'['
  let offset = write_decimal(buf, 2, n)
  buf[offset] = final_byte
  buf.unsafe_reinterpret_as_bytes()
}
