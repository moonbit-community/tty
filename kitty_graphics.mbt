///|
struct KittyGraphicsOptions {
  image_id : Int?
  columns : Int?
  rows : Int?
} derive(Eq)

///|
/// Construct options for `Command::DisplayKittyPng`.
///
/// Non-positive values are ignored when encoding the terminal command.
pub fn KittyGraphicsOptions::new(
  image_id? : Int,
  columns? : Int,
  rows? : Int,
) -> KittyGraphicsOptions {
  { image_id, columns, rows }
}

///|
/// Query whether the terminal supports the Kitty Graphics Protocol.
///
/// User input received while waiting for terminal responses is preserved for
/// later `Tty::read_event` calls.
pub async fn Tty::query_kitty_graphics_support(
  self : Self,
  timeout_ms? : Int = 100,
) -> Bool {
  match
    @async.with_timeout_opt(timeout_ms, () => {
      self.write(@vt.query_kitty_graphics_support)
      self.write(@vt.request_primary_device_attributes)
      for ;; {
        match self.read_internal_event() {
          KittyGraphicsResponse(
            image_id~,
            image_number=_,
            placement_id=_,
            message~
          ) if image_id == @vt.kitty_graphics_query_image_id =>
            return message == "OK"
          KittyGraphicsResponse(..) => ()
          PrimaryDeviceAttributes(_) => return false
          CursorPosition(..) => ()
          KeyboardEnhancementFlags(_) => ()
          DynamicColor(..) => ()
          Input(event) => self.pending_input.push(event)
        }
      }
    }) {
    Some(supported) => supported
    None => false
  }
}

///|
/// Display PNG bytes at the current cursor using the Kitty Graphics Protocol.
///
/// The encoded command uses direct PNG transfer and asks the terminal not to
/// move the text cursor after placing the image. `columns` and `rows`, when
/// positive, set the image placement size in terminal cells.
pub async fn Tty::display_kitty_png(
  self : Self,
  png : BytesView,
  image_id? : Int,
  columns? : Int,
  rows? : Int,
) -> Unit {
  self.write(@vt.display_kitty_png(png, image_id?, columns?, rows?))
}
