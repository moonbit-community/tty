///|
async fn main {
  with_screen(() => @tty.stdin.with_raw_mode(run_cursor_demo))
}

///|
async fn[T] with_screen(f : async () -> T) -> T {
  @tty.stdout.write(@tty/vt.enter_alt_screen)
  @tty.stdout.write(@tty/vt.hide_cursor)
  try f() catch {
    error => {
      restore_screen()
      raise error
    }
  } noraise {
    value => {
      restore_screen()
      value
    }
  }
}

///|
struct Size {
  width : Int
  height : Int
}

///|
struct Anchor {
  top : Int
  left : Int
}

///|
async fn restore_screen() -> Unit {
  @tty.stdout.write(@tty/vt.show_cursor)
  @tty.stdout.write(@tty/vt.leave_alt_screen)
}

///|
fn clamp(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

///|
async fn draw_box(tty : @tty.Output, anchor : Anchor, size : Size) -> Unit {
  tty.write(@tty/vt.cursor_position(anchor.top, anchor.left))
  tty.write("+\{String::make(size.width, '-')}+")
  for row in 1..<=size.height {
    tty.write(@tty/vt.cursor_position(anchor.top + row, anchor.left))
    tty.write("|\{String::make(size.width, ' ')}|")
  }
  tty.write(@tty/vt.cursor_position(anchor.top + size.height + 1, anchor.left))
  tty.write("+\{String::make(size.width, '-')}+")
}

///|
async fn draw_marker(tty : @tty.Output, pos : Anchor, x : Int, y : Int) -> Unit {
  tty.write(@tty/vt.cursor_position(pos.top + 1 + y, pos.left + 1 + x))
  tty.write("@")
}

///|
async fn erase_marker(
  tty : @tty.Output,
  pos : Anchor,
  x : Int,
  y : Int,
) -> Unit {
  tty.write(@tty/vt.cursor_position(pos.top + 1 + y, pos.left + 1 + x))
  tty.write(" ")
}

///|
async fn draw_status(
  tty : @tty.Output,
  pos : Anchor,
  size : Size,
  x : Int,
  y : Int,
  visible : Bool,
) -> Unit {
  tty.write(@tty/vt.cursor_position(pos.top + size.height + 3, pos.left))
  let cursor = if visible { "shown" } else { "hidden" }
  tty.write(
    "WASD/HJKL move  C toggle cursor  Q quit  pos=(\{x},\{y}) cursor=\{cursor}",
  )
  tty.write(String::make(12, ' '))
}

///|
async fn run_cursor_demo() -> Unit {
  let anchor : Anchor = { top: 2, left: 4 }
  let size : Size = { width: 20, height: 10 }
  let mut x = size.width / 2
  let mut y = size.height / 2
  let mut visible = false
  draw_box(@tty.stdout, anchor, size)
  draw_marker(@tty.stdout, anchor, x, y)
  draw_status(@tty.stdout, anchor, size, x, y, visible)
  while true {
    let key = @tty.stdin.read_byte()
    if key == b'q' || key == b'Q' || key == b'\x03' {
      break
    }
    if key == b'c' || key == b'C' {
      visible = !visible
      if visible {
        @tty.stdout.write(@tty/vt.show_cursor)
      } else {
        @tty.stdout.write(@tty/vt.hide_cursor)
      }
      draw_status(@tty.stdout, anchor, size, x, y, visible)
      continue
    }
    let old_x = x
    let old_y = y
    if key == b'w' || key == b'W' || key == b'k' || key == b'K' {
      y = clamp(y - 1, 0, size.height - 1)
    } else if key == b's' || key == b'S' || key == b'j' || key == b'J' {
      y = clamp(y + 1, 0, size.height - 1)
    } else if key == b'a' || key == b'A' || key == b'h' || key == b'H' {
      x = clamp(x - 1, 0, size.width - 1)
    } else if key == b'd' || key == b'D' || key == b'l' || key == b'L' {
      x = clamp(x + 1, 0, size.width - 1)
    }
    if x != old_x || y != old_y {
      erase_marker(@tty.stdout, anchor, old_x, old_y)
      draw_marker(@tty.stdout, anchor, x, y)
      draw_status(@tty.stdout, anchor, size, x, y, visible)
    }
  }
}
