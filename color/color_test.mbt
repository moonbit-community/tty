///|
test "reset sequences" {
  @debug.assert_eq(reset_style, b"\x1b[0m")
  @debug.assert_eq(reset_foreground, b"\x1b[39m")
  @debug.assert_eq(reset_background, b"\x1b[49m")
}

///|
test "basic foreground colors" {
  @debug.assert_eq(foreground(Basic(Black)), b"\x1b[30m")
  @debug.assert_eq(foreground(Basic(Red)), b"\x1b[31m")
  @debug.assert_eq(foreground(Basic(White)), b"\x1b[37m")
  @debug.assert_eq(foreground(Basic(BrightBlack)), b"\x1b[90m")
  @debug.assert_eq(foreground(Basic(BrightRed)), b"\x1b[91m")
  @debug.assert_eq(foreground(Basic(BrightWhite)), b"\x1b[97m")
}

///|
test "basic background colors" {
  @debug.assert_eq(background(Basic(Black)), b"\x1b[40m")
  @debug.assert_eq(background(Basic(Red)), b"\x1b[41m")
  @debug.assert_eq(background(Basic(White)), b"\x1b[47m")
  @debug.assert_eq(background(Basic(BrightBlack)), b"\x1b[100m")
  @debug.assert_eq(background(Basic(BrightRed)), b"\x1b[101m")
  @debug.assert_eq(background(Basic(BrightWhite)), b"\x1b[107m")
}

///|
test "default color resets foreground and background" {
  @debug.assert_eq(foreground(Default), reset_foreground)
  @debug.assert_eq(background(Default), reset_background)
}

///|
test "indexed colors clamp to byte range" {
  @debug.assert_eq(foreground(Indexed(-1)), b"\x1b[38;5;0m")
  @debug.assert_eq(foreground(Indexed(42)), b"\x1b[38;5;42m")
  @debug.assert_eq(foreground(Indexed(999)), b"\x1b[38;5;255m")
  @debug.assert_eq(background(Indexed(-1)), b"\x1b[48;5;0m")
  @debug.assert_eq(background(Indexed(42)), b"\x1b[48;5;42m")
  @debug.assert_eq(background(Indexed(999)), b"\x1b[48;5;255m")
}

///|
test "rgb colors clamp channels to byte range" {
  @debug.assert_eq(foreground(Rgb(-1, 127, 999)), b"\x1b[38;2;0;127;255m")
  @debug.assert_eq(background(Rgb(-1, 127, 999)), b"\x1b[48;2;0;127;255m")
}
