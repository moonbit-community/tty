///|
test "color values compare structurally" {
  @debug.assert_eq(@color.Default, Default)
  @debug.assert_eq(@color.Basic(Red), Basic(Red))
  @debug.assert_eq(@color.Indexed(42), Indexed(42))
  @debug.assert_eq(@color.Rgb(1, 2, 3), Rgb(1, 2, 3))
  @debug.assert_eq(@color.Rgb16::{ red: 1, green: 2, blue: 3 }, {
    red: 1,
    green: 2,
    blue: 3,
  })
}
