///|
/// Compatibility re-export for the semantic color package.
pub using @tty_color {
  type BasicColor,
  type Color,
  background,
  foreground,
  reset_background,
  reset_foreground,
  reset_style,
}

///|
/// Compatibility alias for `reset_style`.
pub let reset_all : Bytes = @tty_color.reset_style
