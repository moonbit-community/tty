///|
pub async fn[T] Tty::with_top_bottom_margins(
  tty : Tty,
  top : Int,
  bottom : Int,
  body : async () -> T,
) -> T {
  tty.set_top_bottom_margins(top, bottom)
  try body() catch {
    error => {
      tty.reset_top_bottom_margins()
      raise error
    }
  } noraise {
    value => {
      tty.reset_top_bottom_margins()
      value
    }
  }
}
