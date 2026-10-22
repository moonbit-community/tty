///|
async fn main {
  let tty = @tty.Tty::open()
  defer tty.close()
  with_screen(tty, () => tty.with_raw_mode(() => run_cursor_demo(tty)))
}

///|
async fn[T] with_screen(tty : @tty.Tty, f : async () -> T) -> T {
  tty.enter_alt_screen()
  tty.hide_cursor()
  defer @async.protect_from_cancel(() => restore_screen(tty))
  f()
}

///|
struct Size {
  width : Int32
  height : Int32
}

///|
struct Anchor {
  top : Int32
  left : Int32
}

///|
async fn restore_screen(tty : @tty.Tty) -> Unit {
  tty.show_cursor()
  tty.leave_alt_screen()
}

///|
fn clamp(value : Int32, min : Int32, max : Int32) -> Int32 {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

///|
async fn draw_box(tty : @tty.Tty, anchor : Anchor, size : Size) -> Unit {
  tty.set_cursor_position(anchor.top, anchor.left)
  tty.write("+\{String::make(size.width, '-')}+")
  for row in 1..<=size.height {
    tty.set_cursor_position(anchor.top + row, anchor.left)
    tty.write("|\{String::make(size.width, ' ')}|")
  }
  tty.set_cursor_position(anchor.top + size.height + 1, anchor.left)
  tty.write("+\{String::make(size.width, '-')}+")
}

///|
async fn draw_marker(
  tty : @tty.Tty,
  pos : Anchor,
  x : Int32,
  y : Int32,
) -> Unit {
  tty.set_cursor_position(pos.top + 1 + y, pos.left + 1 + x)
  tty.write("@")
}

///|
async fn erase_marker(
  tty : @tty.Tty,
  pos : Anchor,
  x : Int32,
  y : Int32,
) -> Unit {
  tty.set_cursor_position(pos.top + 1 + y, pos.left + 1 + x)
  tty.write(" ")
}

///|
async fn draw_status(
  tty : @tty.Tty,
  pos : Anchor,
  size : Size,
  x : Int32,
  y : Int32,
  visible : Bool,
) -> Unit {
  tty.set_cursor_position(pos.top + size.height + 3, pos.left)
  let cursor = if visible { "shown" } else { "hidden" }
  tty.write(
    "WASD/HJKL move  C toggle cursor  Q quit  pos=(\{x},\{y}) cursor=\{cursor}",
  )
  tty.write(String::make(12, ' '))
}

///|
async fn run_cursor_demo(tty : @tty.Tty) -> Unit {
  let anchor : Anchor = { top: 2, left: 4, }
  let size : Size = { width: 20, height: 10, }
  let mut x = size.width / 2
  let mut y = size.height / 2
  let mut visible = false
  draw_box(tty, anchor, size)
  draw_marker(tty, anchor, x, y)
  draw_status(tty, anchor, size, x, y, visible)
  while true {
    guard tty.read_event() is Input(Key({ code: Char(key), .. })) else {
      continue
    }
    if key == 'q' || key == 'Q' {
      break
    }
    if key == 'c' || key == 'C' {
      visible = !visible
      if visible {
        tty.show_cursor()
      } else {
        tty.hide_cursor()
      }
      draw_status(tty, anchor, size, x, y, visible)
      continue
    }
    let old_x = x
    let old_y = y
    if key == 'w' || key == 'W' || key == 'k' || key == 'K' {
      y = clamp(y - 1, 0, size.height - 1)
    } else if key == 's' || key == 'S' || key == 'j' || key == 'J' {
      y = clamp(y + 1, 0, size.height - 1)
    } else if key == 'a' || key == 'A' || key == 'h' || key == 'H' {
      x = clamp(x - 1, 0, size.width - 1)
    } else if key == 'd' || key == 'D' || key == 'l' || key == 'L' {
      x = clamp(x + 1, 0, size.width - 1)
    }
    if x != old_x || y != old_y {
      erase_marker(tty, anchor, old_x, old_y)
      draw_marker(tty, anchor, x, y)
      draw_status(tty, anchor, size, x, y, visible)
    }
  }
}
