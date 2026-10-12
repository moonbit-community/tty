///|
pub struct ControlKeyState(Int32)

///|
pub fn ControlKeyState::has_state(self : ControlKeyState, mask : Int32) -> Bool {
  let ControlKeyState(state) = self
  (state & mask) != 0
}
