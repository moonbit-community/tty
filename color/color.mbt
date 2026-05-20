///|
/// ANSI basic and bright colors.
pub(all) enum BasicColor {
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  BrightBlack
  BrightRed
  BrightGreen
  BrightYellow
  BrightBlue
  BrightMagenta
  BrightCyan
  BrightWhite
} derive(Eq, Debug)

///|
/// Terminal color value for foreground and background style sequences.
pub(all) enum Color {
  Default
  Basic(BasicColor)
  Indexed(Int)
  Rgb(Int, Int, Int)
} derive(Eq, Debug)
