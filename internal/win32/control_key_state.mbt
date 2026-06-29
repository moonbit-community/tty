///|
pub struct ControlKeyState(Int)

///|
pub fn ControlKeyState::has_state(self : ControlKeyState, mask : Int) -> Bool {
  let ControlKeyState(state) = self
  (state & mask) != 0
}
