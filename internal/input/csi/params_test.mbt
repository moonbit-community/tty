///|
test "parse semicolon parameters" {
  @debug.assert_eq(parse_params(b""), Some([]))
  @debug.assert_eq(parse_params(b"12;34"), Some([Some(12), Some(34)]))
  @debug.assert_eq(parse_params(b";5;"), Some([None, Some(5), None]))
}

///|
test "parse semicolon parameters rejects subparams and invalid bytes" {
  @debug.assert_eq(parse_params(b"1:2"), None)
  @debug.assert_eq(parse_params(b"1;?"), None)
}

///|
test "parse colon subparameters" {
  @debug.assert_eq(
    parse_subparams(b"61::99;5:2;229"),
    Some([[Some(61), None, Some(99)], [Some(5), Some(2)], [Some(229)]]),
  )
  @debug.assert_eq(
    parse_subparams(b"0;;229"),
    Some([[Some(0)], [None], [Some(229)]]),
  )
}

///|
test "parse decimal parameter" {
  @debug.assert_eq(parse_decimal(b"0"), Some(0))
  @debug.assert_eq(parse_decimal(b"15"), Some(15))
  @debug.assert_eq(parse_decimal(b""), None)
  @debug.assert_eq(parse_decimal(b"1;2"), None)
}

///|
test "validate primary device attributes parameters" {
  @debug.assert_eq(is_primary_device_attributes_params(b"1"), true)
  @debug.assert_eq(is_primary_device_attributes_params(b"1;2"), true)
  @debug.assert_eq(is_primary_device_attributes_params(b""), false)
  @debug.assert_eq(is_primary_device_attributes_params(b"1;"), false)
  @debug.assert_eq(is_primary_device_attributes_params(b";1"), false)
  @debug.assert_eq(is_primary_device_attributes_params(b"1:x"), false)
}
