///|
test "clamp cursor coordinate" {
  inspect(clamp(-1, 0, 3), content="0")
  inspect(clamp(4, 0, 3), content="3")
  inspect(clamp(2, 0, 3), content="2")
}
