///|
priv struct KeyCode {
  code : @public_input.KeyCode
  keypad : Bool
}

///|
priv struct KeyFields {
  key_codes : Array[Int?]
  modifier_event : Array[Int?]?
  associated_text : Array[Int?]?
}

///|
struct ModifierReport {
  modifiers : @public_input.KeyModifiers
  kind : @public_input.KeyEventKind
  state : @public_input.KeyEventState
}

///|
priv enum ParsedOptionalKeyCode {
  OptionalKeyCode(@public_input.KeyCode?)
  InvalidOptionalKeyCode
}

///|
priv enum ParsedAssociatedText {
  AssociatedText(String?)
  InvalidAssociatedText
}

///|
pub fn ModifierReport::default() -> ModifierReport {
  {
    modifiers: @public_input.KeyModifiers::new(),
    kind: Press,
    state: @public_input.KeyEventState::new(),
  }
}

///|
pub fn ModifierReport::key_event(
  self : ModifierReport,
  code : @public_input.KeyCode,
) -> @public_input.KeyEvent {
  @public_input.KeyEvent::new(
    code,
    modifiers=self.modifiers,
    kind=self.kind,
    state=self.state,
  )
}

///|
pub fn parse_csi_key_report(params : Array[Array[Int?]]) -> ModifierReport? {
  match params {
    [] | [[None | Some(1)]] | [[None | Some(1)], [None]] =>
      Some(ModifierReport::default())
    [[None | Some(1)], modifier] => parse_modifier_report(modifier)
    _ => None
  }
}

///|
pub fn parse_modifier_report(param : Array[Int?]) -> ModifierReport? {
  let (modifier, kind) = match param {
    [None] => (1, 1)
    [Some(modifier)] => (modifier, 1)
    [Some(modifier), Some(kind)] => (modifier, kind)
    _ => return None
  }
  guard modifier >= 1 else { return None }
  guard parse_key_event_kind(kind) is Some(kind) else { return None }
  let bits = modifier - 1
  Some({
    modifiers: @public_input.KeyModifiers::new(
      shift=(bits & 1) != 0,
      alt=(bits & 2) != 0,
      ctrl=(bits & 4) != 0,
      super_=(bits & 8) != 0,
      hyper=(bits & 16) != 0,
      meta=(bits & 32) != 0,
    ),
    kind,
    state: @public_input.KeyEventState::new(
      caps_lock=(bits & 64) != 0,
      num_lock=(bits & 128) != 0,
    ),
  })
}

///|
fn parse_key_event_kind(kind : Int) -> @public_input.KeyEventKind? {
  match kind {
    1 => Some(Press)
    2 => Some(Repeat)
    3 => Some(Release)
    _ => None
  }
}

///|
fn parse_key_fields(params : Array[Array[Int?]]) -> KeyFields? {
  match params {
    [key_codes] =>
      Some({ key_codes, modifier_event: None, associated_text: None })
    [key_codes, modifier_event] =>
      Some({
        key_codes,
        modifier_event: Some(modifier_event),
        associated_text: None,
      })
    [key_codes, modifier_event, associated_text] =>
      Some({
        key_codes,
        modifier_event: Some(modifier_event),
        associated_text: Some(associated_text),
      })
    _ => None
  }
}

///|
fn key_event_from_parts(
  code : @public_input.KeyCode,
  modifiers : @public_input.KeyModifiers,
  kind : @public_input.KeyEventKind,
  state : @public_input.KeyEventState,
  text : String?,
  shifted_code : @public_input.KeyCode?,
  base_code : @public_input.KeyCode?,
) -> @public_input.KeyEvent {
  match (text, shifted_code, base_code) {
    (Some(text), Some(shifted_code), Some(base_code)) =>
      @public_input.KeyEvent::new(
        code,
        modifiers~,
        kind~,
        state~,
        text~,
        shifted_code~,
        base_code~,
      )
    (Some(text), Some(shifted_code), None) =>
      @public_input.KeyEvent::new(
        code,
        modifiers~,
        kind~,
        state~,
        text~,
        shifted_code~,
      )
    (Some(text), None, Some(base_code)) =>
      @public_input.KeyEvent::new(
        code,
        modifiers~,
        kind~,
        state~,
        text~,
        base_code~,
      )
    (Some(text), None, None) =>
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~, text~)
    (None, Some(shifted_code), Some(base_code)) =>
      @public_input.KeyEvent::new(
        code,
        modifiers~,
        kind~,
        state~,
        shifted_code~,
        base_code~,
      )
    (None, Some(shifted_code), None) =>
      @public_input.KeyEvent::new(
        code,
        modifiers~,
        kind~,
        state~,
        shifted_code~,
      )
    (None, None, Some(base_code)) =>
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~, base_code~)
    (None, None, None) =>
      @public_input.KeyEvent::new(code, modifiers~, kind~, state~)
  }
}

///|
pub fn parse_key(params : Array[Array[Int?]]) -> @public_input.KeyEvent? {
  guard parse_key_fields(params) is Some(fields) else { return None }
  guard fields.key_codes.length() > 0 && fields.key_codes.length() <= 3 else {
    return None
  }
  guard fields.key_codes is [Some(codepoint), ..] else { return None }
  guard key_code_from_codepoint(codepoint) is Some(parsed_code) else {
    return None
  }
  let modifier_report = match fields.modifier_event {
    Some(modifier_event) =>
      match parse_modifier_report(modifier_event) {
        Some(report) => report
        None => return None
      }
    None => ModifierReport::default()
  }
  let modifiers = match fields.modifier_event {
    Some(_) => modifier_report.modifiers
    None =>
      modifiers_with_modifier_key(parsed_code.code, modifier_report.modifiers)
  }
  let shifted_code = match parse_optional_key_code(fields.key_codes, 1) {
    OptionalKeyCode(code) => code
    InvalidOptionalKeyCode => return None
  }
  let base_code = match parse_optional_key_code(fields.key_codes, 2) {
    OptionalKeyCode(code) => code
    InvalidOptionalKeyCode => return None
  }
  match shifted_code {
    Some(_) if !modifiers.shift() => return None
    _ => ()
  }
  let associated_text = match fields.associated_text {
    Some(associated_text) =>
      match parse_associated_text(associated_text) {
        AssociatedText(text) => text
        InvalidAssociatedText => return None
      }
    None => default_key_text(parsed_code.code, modifiers, shifted_code)
  }
  match (parsed_code.code, associated_text) {
    (Text, None) => return None
    _ => ()
  }
  Some(
    key_event_from_parts(
      parsed_code.code,
      modifiers,
      modifier_report.kind,
      @public_input.KeyEventState::new(
        keypad=parsed_code.keypad || modifier_report.state.keypad(),
        caps_lock=modifier_report.state.caps_lock(),
        num_lock=modifier_report.state.num_lock(),
      ),
      associated_text,
      shifted_code,
      base_code,
    ),
  )
}

///|
fn modifiers_with_modifier_key(
  code : @public_input.KeyCode,
  modifiers : @public_input.KeyModifiers,
) -> @public_input.KeyModifiers {
  match code {
    Modifier(LeftShift | RightShift) =>
      @public_input.KeyModifiers::new(
        shift=true,
        alt=modifiers.alt(),
        ctrl=modifiers.ctrl(),
        meta=modifiers.meta(),
        super_=modifiers.super_(),
        hyper=modifiers.hyper(),
      )
    Modifier(LeftAlt | RightAlt) =>
      @public_input.KeyModifiers::new(
        shift=modifiers.shift(),
        alt=true,
        ctrl=modifiers.ctrl(),
        meta=modifiers.meta(),
        super_=modifiers.super_(),
        hyper=modifiers.hyper(),
      )
    Modifier(LeftControl | RightControl) =>
      @public_input.KeyModifiers::new(
        shift=modifiers.shift(),
        alt=modifiers.alt(),
        ctrl=true,
        meta=modifiers.meta(),
        super_=modifiers.super_(),
        hyper=modifiers.hyper(),
      )
    Modifier(LeftSuper | RightSuper) =>
      @public_input.KeyModifiers::new(
        shift=modifiers.shift(),
        alt=modifiers.alt(),
        ctrl=modifiers.ctrl(),
        meta=modifiers.meta(),
        super_=true,
        hyper=modifiers.hyper(),
      )
    Modifier(LeftHyper | RightHyper) =>
      @public_input.KeyModifiers::new(
        shift=modifiers.shift(),
        alt=modifiers.alt(),
        ctrl=modifiers.ctrl(),
        meta=modifiers.meta(),
        super_=modifiers.super_(),
        hyper=true,
      )
    Modifier(LeftMeta | RightMeta) =>
      @public_input.KeyModifiers::new(
        shift=modifiers.shift(),
        alt=modifiers.alt(),
        ctrl=modifiers.ctrl(),
        meta=true,
        super_=modifiers.super_(),
        hyper=modifiers.hyper(),
      )
    _ => modifiers
  }
}

///|
fn parse_optional_key_code(
  param : Array[Int?],
  index : Int,
) -> ParsedOptionalKeyCode {
  if index >= param.length() {
    return OptionalKeyCode(None)
  }
  match param[index] {
    None => OptionalKeyCode(None)
    Some(codepoint) =>
      match key_code_from_codepoint(codepoint) {
        Some(parsed) =>
          match parsed.code {
            Text => InvalidOptionalKeyCode
            _ => OptionalKeyCode(Some(parsed.code))
          }
        None => InvalidOptionalKeyCode
      }
  }
}

///|
fn parse_associated_text(param : Array[Int?]) -> ParsedAssociatedText {
  let builder = StringBuilder()
  let mut seen = false
  for part in param {
    match part {
      Some(codepoint) if codepoint.to_char() is Some(ch) && !ch.is_control() => {
        builder.write_char(ch)
        seen = true
      }
      Some(_) => return InvalidAssociatedText
      None => return InvalidAssociatedText
    }
  }
  if seen {
    AssociatedText(Some(builder.to_string()))
  } else {
    AssociatedText(None)
  }
}

///|
fn default_key_text(
  code : @public_input.KeyCode,
  modifiers : @public_input.KeyModifiers,
  shifted_code : @public_input.KeyCode?,
) -> String? {
  if modifiers.ctrl() ||
    modifiers.alt() ||
    modifiers.meta() ||
    modifiers.super_() ||
    modifiers.hyper() {
    return None
  }
  match (modifiers.shift(), shifted_code) {
    (true, Some(Char(ch))) if ch.is_printable() => Some([ch])
    (true, _) => None
    _ =>
      match code {
        Char(ch) if ch.is_printable() => Some([ch])
        Keypad0 => Some("0")
        Keypad1 => Some("1")
        Keypad2 => Some("2")
        Keypad3 => Some("3")
        Keypad4 => Some("4")
        Keypad5 => Some("5")
        Keypad6 => Some("6")
        Keypad7 => Some("7")
        Keypad8 => Some("8")
        Keypad9 => Some("9")
        KeypadDecimal => Some(".")
        KeypadDivide => Some("/")
        KeypadMultiply => Some("*")
        KeypadMinus => Some("-")
        KeypadPlus => Some("+")
        KeypadEqual => Some("=")
        KeypadSeparator => Some(",")
        _ => None
      }
  }
}

///|
fn key_code_from_codepoint(codepoint : Int) -> KeyCode? {
  if key_code_from_functional_key(codepoint) is Some(key) {
    return Some(key)
  }
  match codepoint {
    0 => Some({ code: Text, keypad: false })
    9 => Some({ code: Tab, keypad: false })
    13 => Some({ code: Enter, keypad: false })
    27 => Some({ code: Escape, keypad: false })
    127 => Some({ code: Backspace, keypad: false })
    _ =>
      match codepoint.to_char() {
        Some(ch) if ch.is_printable() => Some({ code: Char(ch), keypad: false })
        _ => None
      }
  }
}

///|
fn key_code_from_functional_key(codepoint : Int) -> KeyCode? {
  match codepoint {
    57358 => Some({ code: CapsLock, keypad: false })
    57359 => Some({ code: ScrollLock, keypad: false })
    57360 => Some({ code: NumLock, keypad: false })
    57361 => Some({ code: PrintScreen, keypad: false })
    57362 => Some({ code: Pause, keypad: false })
    57363 => Some({ code: Menu, keypad: false })
    57376 => Some({ code: F13, keypad: false })
    57377 => Some({ code: F14, keypad: false })
    57378 => Some({ code: F15, keypad: false })
    57379 => Some({ code: F16, keypad: false })
    57380 => Some({ code: F17, keypad: false })
    57381 => Some({ code: F18, keypad: false })
    57382 => Some({ code: F19, keypad: false })
    57383 => Some({ code: F20, keypad: false })
    57384 => Some({ code: F21, keypad: false })
    57385 => Some({ code: F22, keypad: false })
    57386 => Some({ code: F23, keypad: false })
    57387 => Some({ code: F24, keypad: false })
    57388 => Some({ code: F25, keypad: false })
    57389 => Some({ code: F26, keypad: false })
    57390 => Some({ code: F27, keypad: false })
    57391 => Some({ code: F28, keypad: false })
    57392 => Some({ code: F29, keypad: false })
    57393 => Some({ code: F30, keypad: false })
    57394 => Some({ code: F31, keypad: false })
    57395 => Some({ code: F32, keypad: false })
    57396 => Some({ code: F33, keypad: false })
    57397 => Some({ code: F34, keypad: false })
    57398 => Some({ code: F35, keypad: false })
    57399 => Some({ code: Keypad0, keypad: true })
    57400 => Some({ code: Keypad1, keypad: true })
    57401 => Some({ code: Keypad2, keypad: true })
    57402 => Some({ code: Keypad3, keypad: true })
    57403 => Some({ code: Keypad4, keypad: true })
    57404 => Some({ code: Keypad5, keypad: true })
    57405 => Some({ code: Keypad6, keypad: true })
    57406 => Some({ code: Keypad7, keypad: true })
    57407 => Some({ code: Keypad8, keypad: true })
    57408 => Some({ code: Keypad9, keypad: true })
    57409 => Some({ code: KeypadDecimal, keypad: true })
    57410 => Some({ code: KeypadDivide, keypad: true })
    57411 => Some({ code: KeypadMultiply, keypad: true })
    57412 => Some({ code: KeypadMinus, keypad: true })
    57413 => Some({ code: KeypadPlus, keypad: true })
    57414 => Some({ code: KeypadEnter, keypad: true })
    57415 => Some({ code: KeypadEqual, keypad: true })
    57416 => Some({ code: KeypadSeparator, keypad: true })
    57417 => Some({ code: Left, keypad: true })
    57418 => Some({ code: Right, keypad: true })
    57419 => Some({ code: Up, keypad: true })
    57420 => Some({ code: Down, keypad: true })
    57421 => Some({ code: PageUp, keypad: true })
    57422 => Some({ code: PageDown, keypad: true })
    57423 => Some({ code: Home, keypad: true })
    57424 => Some({ code: End, keypad: true })
    57425 => Some({ code: Insert, keypad: true })
    57426 => Some({ code: Delete, keypad: true })
    57427 => Some({ code: KeypadBegin, keypad: true })
    57428 => Some({ code: Media(Play), keypad: false })
    57429 => Some({ code: Media(Pause), keypad: false })
    57430 => Some({ code: Media(PlayPause), keypad: false })
    57431 => Some({ code: Media(Reverse), keypad: false })
    57432 => Some({ code: Media(Stop), keypad: false })
    57433 => Some({ code: Media(FastForward), keypad: false })
    57434 => Some({ code: Media(Rewind), keypad: false })
    57435 => Some({ code: Media(TrackNext), keypad: false })
    57436 => Some({ code: Media(TrackPrevious), keypad: false })
    57437 => Some({ code: Media(Record), keypad: false })
    57438 => Some({ code: Media(LowerVolume), keypad: false })
    57439 => Some({ code: Media(RaiseVolume), keypad: false })
    57440 => Some({ code: Media(MuteVolume), keypad: false })
    57441 => Some({ code: Modifier(LeftShift), keypad: false })
    57442 => Some({ code: Modifier(LeftControl), keypad: false })
    57443 => Some({ code: Modifier(LeftAlt), keypad: false })
    57444 => Some({ code: Modifier(LeftSuper), keypad: false })
    57445 => Some({ code: Modifier(LeftHyper), keypad: false })
    57446 => Some({ code: Modifier(LeftMeta), keypad: false })
    57447 => Some({ code: Modifier(RightShift), keypad: false })
    57448 => Some({ code: Modifier(RightControl), keypad: false })
    57449 => Some({ code: Modifier(RightAlt), keypad: false })
    57450 => Some({ code: Modifier(RightSuper), keypad: false })
    57451 => Some({ code: Modifier(RightHyper), keypad: false })
    57452 => Some({ code: Modifier(RightMeta), keypad: false })
    57453 => Some({ code: Modifier(IsoLevel3Shift), keypad: false })
    57454 => Some({ code: Modifier(IsoLevel5Shift), keypad: false })
    _ => None
  }
}
