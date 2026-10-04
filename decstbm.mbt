///|
pub async fn[T] Tty::with_top_bottom_margins(
  tty : Tty,
  top : Int,
  bottom : Int,
  body : async () -> T,
) -> T {
  tty.set_top_bottom_margins(top, bottom)
  defer @async.protect_from_cancel(() => tty.reset_top_bottom_margins())
  body()
}
