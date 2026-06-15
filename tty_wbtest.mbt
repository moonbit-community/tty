///|
async fn with_pipe_tty(f : async (Tty) -> Unit) -> String {
  let (input, input_writer) = @async/pipe.pipe()
  let (output_reader, output) = @async/pipe.pipe()
  defer output_reader.close()
  input_writer.close()
  {
    let tty = Tty::new(input, output)
    defer tty.close()
    f(tty)
  }
  output_reader.read_all().text()
}

///|
test "state buffer can be made raw" {
  assert_true(sizeof_state > 0)
  let state = State::new()
  @debug.assert_eq(state.0.length(), sizeof_state)
  let raw = state.make_raw()
  @debug.assert_eq(raw.0.length(), sizeof_state)
}

///|
async test "tty state operations reject non tty pipe" {
  ignore(
    with_pipe_tty(tty => {
      let state = State::new()
      try tty.get_state() catch {
        _ => ()
      } noraise {
        _ => fail("expected get_state to reject non tty pipe")
      }
      try tty.set_state(state) catch {
        _ => ()
      } noraise {
        _ => fail("expected set_state to reject non tty pipe")
      }
      try tty.enter_raw_mode() catch {
        _ => ()
      } noraise {
        _ => fail("expected enter_raw_mode to reject non tty pipe")
      }
      try tty.leave_raw_mode(state) catch {
        _ => ()
      } noraise {
        _ => fail("expected leave_raw_mode to reject non tty pipe")
      }
      try tty.with_raw_mode(() => ()) catch {
        _ => ()
      } noraise {
        _ => fail("expected with_raw_mode to reject non tty pipe")
      }
    }),
  )
}
