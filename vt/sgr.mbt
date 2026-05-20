///|
/// Construct an SGR sequence with one parameter.
pub fn sgr1(p1 : Int) -> Bytes {
  @seq.sgr1(p1)
}

///|
/// Construct an SGR sequence with three parameters.
pub fn sgr3(p1 : Int, p2 : Int, p3 : Int) -> Bytes {
  @seq.sgr3(p1, p2, p3)
}

///|
/// Construct an SGR sequence with five parameters.
pub fn sgr5(p1 : Int, p2 : Int, p3 : Int, p4 : Int, p5 : Int) -> Bytes {
  @seq.sgr5(p1, p2, p3, p4, p5)
}
