///|
test "root value types debug print" {
  debug_inspect(
    CursorPosition::{ row: 3, col: 4, },
    content=(
      #|{ row: 3, col: 4 }
    ),
  )
  debug_inspect(
    Event::Resize({ rows: 24, cols: 80, }),
    content=(
      #|Resize({ rows: 24, cols: 80 })
    ),
  )
}
