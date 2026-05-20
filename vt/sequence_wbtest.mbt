///|
test "csi sequences" {
  @debug.assert_eq(csi1(1, b'A'), b"\x1b[1A")
  @debug.assert_eq(csi1(12, b'B'), b"\x1b[12B")
  @debug.assert_eq(csi2(1, 1, b'H'), b"\x1b[1;1H")
  @debug.assert_eq(csi2(12, 34, b'H'), b"\x1b[12;34H")
}

///|
test "panic count decimal digits rejects negative input" {
  ignore(count_decimal_digits(-1))
}
