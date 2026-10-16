///|
priv enum InputRecord {
  Character(code_unit~ : Int32, repeat_count~ : Int32)
  Resize
  Ignored
}

///|
fn InputRecord::parse(record : Bytes) -> InputRecord {
  match record[:] {
    [
      u16le(1),
      u16le(_),
      u32le(down),
      u16le(repeat),
      u16le(_),
      u16le(_),
      u16le(char),
      ..,
    ] if down != 0 && char != 0 =>
      Character(
        code_unit=char.reinterpret_as_int(),
        repeat_count=repeat.reinterpret_as_int(),
      )
    [u16le(4), ..] => Resize
    _ => Ignored
  }
}
