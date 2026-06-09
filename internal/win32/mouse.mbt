///|
#cfg(platform="windows")
pub fn MouseButtonState::input_event(
  self : MouseButtonState,
  record : MouseRecord,
) -> @public_input.InputEvent? {
  match self.event_kind(record) {
    Some(kind) =>
      Some(
        Mouse(
          @public_input.MouseEvent::new(
            kind,
            record.y + 1,
            record.x + 1,
            modifiers=record.modifiers(),
          ),
        ),
      )
    None => None
  }
}

///|
#cfg(platform="windows")
fn MouseButtonState::event_kind(
  self : MouseButtonState,
  record : MouseRecord,
) -> @public_input.MouseEventKind? {
  let buttons = record.button_state & MouseButtonMask
  match record.event_flags {
    0 => {
      let previous = self.buttons
      self.buttons = buttons
      match newly_pressed_mouse_button(previous, buttons) {
        Some(button) => Some(Press(button))
        None =>
          newly_released_mouse_button(previous, buttons).map(button => {
            Release(button)
          })
      }
    }
    MouseMoved => {
      self.buttons = buttons
      match mouse_button_from_state(buttons) {
        Some(button) => Some(Drag(button))
        None => Some(Move)
      }
    }
    MouseDoubleClick => {
      self.buttons = buttons
      mouse_button_from_state(buttons).map(button => Press(button))
    }
    MouseWheeled => {
      self.buttons = buttons
      let delta = signed_high_word(record.button_state)
      if delta > 0 {
        Some(Scroll(Up))
      } else if delta < 0 {
        Some(Scroll(Down))
      } else {
        None
      }
    }
    MouseHorizontalWheeled => {
      self.buttons = buttons
      let delta = signed_high_word(record.button_state)
      if delta > 0 {
        Some(Scroll(Right))
      } else if delta < 0 {
        Some(Scroll(Left))
      } else {
        None
      }
    }
    _ => {
      self.buttons = buttons
      None
    }
  }
}

///|
#cfg(platform="windows")
fn MouseRecord::modifiers(self : MouseRecord) -> @public_input.KeyModifiers {
  modifiers_from_control_key_state(self.control_key_state)
}

///|
#cfg(platform="windows")
fn newly_pressed_mouse_button(
  previous : Int,
  buttons : Int,
) -> @public_input.MouseButton? {
  if (buttons & MouseLeftButton) != 0 && (previous & MouseLeftButton) == 0 {
    Some(Left)
  } else if (buttons & MouseMiddleButton) != 0 &&
    (previous & MouseMiddleButton) == 0 {
    Some(Middle)
  } else if (buttons & MouseRightButton) != 0 &&
    (previous & MouseRightButton) == 0 {
    Some(Right)
  } else {
    None
  }
}

///|
#cfg(platform="windows")
fn newly_released_mouse_button(
  previous : Int,
  buttons : Int,
) -> @public_input.MouseButton? {
  if (previous & MouseLeftButton) != 0 && (buttons & MouseLeftButton) == 0 {
    Some(Left)
  } else if (previous & MouseMiddleButton) != 0 &&
    (buttons & MouseMiddleButton) == 0 {
    Some(Middle)
  } else if (previous & MouseRightButton) != 0 &&
    (buttons & MouseRightButton) == 0 {
    Some(Right)
  } else {
    None
  }
}

///|
#cfg(platform="windows")
fn mouse_button_from_state(state : Int) -> @public_input.MouseButton? {
  if (state & MouseLeftButton) != 0 {
    Some(Left)
  } else if (state & MouseMiddleButton) != 0 {
    Some(Middle)
  } else if (state & MouseRightButton) != 0 {
    Some(Right)
  } else {
    None
  }
}

///|
#cfg(platform="windows")
fn signed_high_word(value : Int) -> Int {
  let low_word = value & 0xffff
  (value - low_word) / 0x10000
}

///|
#cfg(platform="windows")
fn modifiers_from_control_key_state(state : Int) -> @public_input.KeyModifiers {
  @public_input.KeyModifiers::new(
    shift=has_state(state, ShiftPressed),
    alt=has_state(state, LeftAltPressed | RightAltPressed),
    ctrl=has_state(state, LeftCtrlPressed | RightCtrlPressed),
  )
}
