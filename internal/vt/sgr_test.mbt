///|
test "sgr sequences" {
  @debug.assert_eq(@vt.bold, b"\x1b[1m")
  @debug.assert_eq(@vt.reset_bold, b"\x1b[22m")
  @debug.assert_eq(@vt.italic, b"\x1b[3m")
  @debug.assert_eq(@vt.reset_italic, b"\x1b[23m")
  @debug.assert_eq(@vt.underline, b"\x1b[4m")
  @debug.assert_eq(@vt.reset_underline, b"\x1b[24m")
  @debug.assert_eq(@vt.reverse, b"\x1b[7m")
  @debug.assert_eq(@vt.reset_reverse, b"\x1b[27m")
  @debug.assert_eq(@vt.reset_style, b"\x1b[0m")
  @debug.assert_eq(@vt.reset_foreground, b"\x1b[39m")
  @debug.assert_eq(@vt.reset_background, b"\x1b[49m")
  @debug.assert_eq(@vt.sgr1(0), b"\x1b[0m")
  @debug.assert_eq(@vt.sgr3(38, 5, 42), b"\x1b[38;5;42m")
  @debug.assert_eq(@vt.sgr5(38, 2, 1, 127, 255), b"\x1b[38;2;1;127;255m")
}

///|
test "sgr color sequences encode semantic colors" {
  @debug.assert_eq(@vt.set_foreground(Default), b"\x1b[39m")
  @debug.assert_eq(@vt.set_foreground(Basic(Black)), b"\x1b[30m")
  @debug.assert_eq(@vt.set_foreground(Basic(Red)), b"\x1b[31m")
  @debug.assert_eq(@vt.set_foreground(Basic(White)), b"\x1b[37m")
  @debug.assert_eq(@vt.set_foreground(Basic(BrightBlack)), b"\x1b[90m")
  @debug.assert_eq(@vt.set_foreground(Basic(BrightRed)), b"\x1b[91m")
  @debug.assert_eq(@vt.set_foreground(Basic(BrightWhite)), b"\x1b[97m")
  @debug.assert_eq(@vt.set_background(Default), b"\x1b[49m")
  @debug.assert_eq(@vt.set_background(Basic(Black)), b"\x1b[40m")
  @debug.assert_eq(@vt.set_background(Basic(Red)), b"\x1b[41m")
  @debug.assert_eq(@vt.set_background(Basic(White)), b"\x1b[47m")
  @debug.assert_eq(@vt.set_background(Basic(BrightBlack)), b"\x1b[100m")
  @debug.assert_eq(@vt.set_background(Basic(BrightRed)), b"\x1b[101m")
  @debug.assert_eq(@vt.set_background(Basic(BrightWhite)), b"\x1b[107m")
  @debug.assert_eq(@vt.set_foreground(Indexed(-1)), b"\x1b[38;5;0m")
  @debug.assert_eq(@vt.set_foreground(Indexed(42)), b"\x1b[38;5;42m")
  @debug.assert_eq(@vt.set_foreground(Indexed(999)), b"\x1b[38;5;255m")
  @debug.assert_eq(@vt.set_background(Indexed(-1)), b"\x1b[48;5;0m")
  @debug.assert_eq(@vt.set_background(Indexed(42)), b"\x1b[48;5;42m")
  @debug.assert_eq(@vt.set_background(Indexed(999)), b"\x1b[48;5;255m")
  @debug.assert_eq(
    @vt.set_foreground(Rgb(-1, 127, 999)),
    b"\x1b[38;2;0;127;255m",
  )
  @debug.assert_eq(
    @vt.set_background(Rgb(-1, 127, 999)),
    b"\x1b[48;2;0;127;255m",
  )
}
