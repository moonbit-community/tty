///|
/// Set Top and Bottom Margins (DECSTBM), DEC private sequence.
///
/// `top` and `bottom` are 1-based inclusive rows. Values less than 1 are
/// treated as 1. If `bottom` is less than `top`, it is treated as `top`.
pub fn set_top_bottom_margins(top : Int, bottom : Int) -> Bytes {
  let top = if top <= 1 { 1 } else { top }
  let bottom = if bottom < top { top } else { bottom }
  csi2(top, bottom, b'r')
}

///|
/// Reset Top and Bottom Margins (DECSTBM), DEC private sequence.
pub let reset_top_bottom_margins : Bytes = b"\x1b[r"

///|
/// Reverse Index (RI), ECMA-48.
pub let reverse_index : Bytes = b"\x1bM"
