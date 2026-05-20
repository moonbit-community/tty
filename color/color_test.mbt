///|
test "color values compare structurally" {
  @debug.assert_eq(@color.Default, @color.Default)
  @debug.assert_eq(@color.Basic(@color.Red), @color.Basic(@color.Red))
  @debug.assert_eq(@color.Indexed(42), @color.Indexed(42))
  @debug.assert_eq(@color.Rgb(1, 2, 3), @color.Rgb(1, 2, 3))
}
