///|
const DecimalBenchSampleCount = 256

///|
fn count_decimal_digits(n : Int) -> Int {
  guard n >= 0 else {
    abort("count_decimal_digits: n should be greater or equal to 0")
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
fn decimal_bytes_string_utf8(n : Int) -> Bytes {
  @utf8.encode("\{n}")
}

///|
fn decimal_bytes_manual_recount(n : Int) -> Bytes {
  let len = count_decimal_digits(n)
  let buf : FixedArray[Byte] = FixedArray::make(len, 0)
  ignore(write_decimal_digits(buf, n))
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn decimal_bytes_manual_counted(n : Int) -> Bytes {
  let len = count_decimal_digits(n)
  let buf : FixedArray[Byte] = FixedArray::make(len, 0)
  ignore(write_decimal_digits(buf, n, length=len))
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn decimal_bytes_scratch_copy(n : Int) -> Bytes {
  let scratch : FixedArray[Byte] = FixedArray::make(20, 0)
  decimal_bytes_scratch_reuse(n, scratch)
}

///|
fn decimal_bytes_scratch_reuse(n : Int, scratch : FixedArray[Byte]) -> Bytes {
  let mut value = n
  let mut pos = scratch.length()
  while true {
    pos -= 1
    scratch[pos] = (value % 10 + b'0'.to_int()).to_byte()
    value = value / 10
    if value == 0 {
      break
    }
  }
  let len = scratch.length() - pos
  let buf : FixedArray[Byte] = FixedArray::make(len, 0)
  FixedArray::unsafe_blit(buf, 0, scratch, pos, len)
  buf.unsafe_reinterpret_as_bytes()
}

///|
fn decimal_bytes_fast_small(n : Int) -> Bytes {
  if n < 10 {
    let buf : FixedArray[Byte] = FixedArray::make(1, 0)
    buf[0] = (n + b'0'.to_int()).to_byte()
    buf.unsafe_reinterpret_as_bytes()
  } else if n < 100 {
    let buf : FixedArray[Byte] = FixedArray::make(2, 0)
    buf[0] = (n / 10 + b'0'.to_int()).to_byte()
    buf[1] = (n % 10 + b'0'.to_int()).to_byte()
    buf.unsafe_reinterpret_as_bytes()
  } else {
    decimal_bytes_manual_counted(n)
  }
}

///|
fn make_decimal_bench_inputs(limit : Int) -> FixedArray[Int] {
  let rng = @random.Rand::new()
  FixedArray::makei(DecimalBenchSampleCount, _ => rng.int(limit~))
}

///|
fn bench_decimal_bytes(
  b : @bench.T,
  name : String,
  inputs : FixedArray[Int],
  write : (Int) -> Bytes,
) -> Unit {
  b.bench(
    () => {
      let mut total = 0
      let mut last = b""
      for n in inputs {
        last = write(n)
        total += last.length()
      }
      b.keep((total, last))
    },
    name~,
  )
}

///|
test "decimal byte writers agree" {
  let cases = [0, 1, 9, 10, 42, 99, 100, 999, 1000, 1234567890]
  let scratch : FixedArray[Byte] = FixedArray::make(20, 0)
  for n in cases {
    let expected = decimal_bytes_string_utf8(n)
    assert_eq(decimal_bytes_manual_recount(n), expected)
    assert_eq(decimal_bytes_manual_counted(n), expected)
    assert_eq(decimal_bytes_scratch_copy(n), expected)
    assert_eq(decimal_bytes_scratch_reuse(n, scratch), expected)
    assert_eq(decimal_bytes_fast_small(n), expected)
  }
}

///|
test "bench decimal bytes small n<100" (b : @bench.T) {
  let inputs = make_decimal_bench_inputs(100)
  bench_decimal_bytes(b, "string_utf8", inputs, decimal_bytes_string_utf8)
  bench_decimal_bytes(b, "manual_recount", inputs, decimal_bytes_manual_recount)
  bench_decimal_bytes(b, "manual_counted", inputs, decimal_bytes_manual_counted)
  bench_decimal_bytes(b, "scratch_copy", inputs, decimal_bytes_scratch_copy)
  let scratch : FixedArray[Byte] = FixedArray::make(20, 0)
  bench_decimal_bytes(b, "scratch_reuse", inputs, n => {
    decimal_bytes_scratch_reuse(n, scratch)
  })
  bench_decimal_bytes(b, "fast_small", inputs, decimal_bytes_fast_small)
}

///|
test "bench decimal bytes mixed n<1_000_000" (b : @bench.T) {
  let inputs = make_decimal_bench_inputs(1_000_000)
  bench_decimal_bytes(b, "string_utf8", inputs, decimal_bytes_string_utf8)
  bench_decimal_bytes(b, "manual_recount", inputs, decimal_bytes_manual_recount)
  bench_decimal_bytes(b, "manual_counted", inputs, decimal_bytes_manual_counted)
  bench_decimal_bytes(b, "scratch_copy", inputs, decimal_bytes_scratch_copy)
  let scratch : FixedArray[Byte] = FixedArray::make(20, 0)
  bench_decimal_bytes(b, "scratch_reuse", inputs, n => {
    decimal_bytes_scratch_reuse(n, scratch)
  })
  bench_decimal_bytes(b, "fast_small", inputs, decimal_bytes_fast_small)
}
