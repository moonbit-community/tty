///|
#cfg(not(platform="windows"))
test "non-Windows public input import anchor" {
  let _ : @public_input.InputEvent? = None
}
