///|
/// Parse semicolon-separated CSI parameters.
pub fn parse_params(params_bytes : BytesView) -> Array[Int?]? {
  let parsed = parse_subparams(params_bytes)
  guard parsed is Some(params) else { return None }
  let flattened : Array[Int?] = []
  for param in params {
    guard param.length() == 1 else { return None }
    flattened.push(param[0])
  }
  Some(flattened)
}

///|
/// Parse semicolon-separated CSI parameters with colon subparameters.
pub fn parse_subparams(params_bytes : BytesView) -> Array[Array[Int?]]? {
  let params : Array[Array[Int?]] = []
  if params_bytes.length() == 0 {
    return Some(params)
  }
  let mut param : Array[Int?] = []
  let mut value = 0
  let mut seen = false
  for i = 0; i < params_bytes.length(); {
    let byte = params_bytes[i]
    match byte {
      b'0'..=b'9' => {
        seen = true
        value = value * 10 + byte.to_int() - b'0'.to_int()
        continue i + 1
      }
      b':' => {
        param.push(if seen { Some(value) } else { None })
        value = 0
        seen = false
        continue i + 1
      }
      b';' => {
        param.push(if seen { Some(value) } else { None })
        params.push(param)
        param = []
        value = 0
        seen = false
        continue i + 1
      }
      _ => return None
    }
  }
  param.push(if seen { Some(value) } else { None })
  params.push(param)
  Some(params)
}

///|
/// Parse a non-empty decimal CSI parameter payload.
pub fn parse_decimal(params : BytesView) -> Int? {
  guard params.length() > 0 else { return None }
  let mut value = 0
  for i = 0; i < params.length(); {
    let byte = params[i]
    match byte {
      b'0'..=b'9' => {
        value = value * 10 + byte.to_int() - b'0'.to_int()
        continue i + 1
      }
      _ => return None
    }
  }
  Some(value)
}

///|
/// Return whether params are a valid Primary Device Attributes payload.
pub fn is_primary_device_attributes_params(params : BytesView) -> Bool {
  guard params.length() > 0 else { return false }
  let mut part_has_digit = false
  for i = 0; i < params.length(); {
    let byte = params[i]
    match byte {
      b'0'..=b'9' => {
        part_has_digit = true
        continue i + 1
      }
      b';' if part_has_digit => {
        part_has_digit = false
        continue i + 1
      }
      _ => return false
    }
  }
  part_has_digit
}
