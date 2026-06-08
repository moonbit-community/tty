///|
#cfg(platform="windows")
fn win32_test_key_record(char : Char) -> Win32InputRecord {
  {
    event_type: Win32RecordKey,
    key_down: 1,
    repeat_count: 1,
    virtual_key_code: 0,
    unicode_char: char.to_int(),
    control_key_state: 0,
    focus_set: 0,
  }
}

///|
#cfg(platform="windows")
async test "win32 console source decodes bracketed paste key records" {
  let (dummy_input, dummy_output) = @async/pipe.pipe()
  defer dummy_input.close()
  defer dummy_output.close()
  let source = Win32ConsoleInputSource::new(dummy_input.fd(), dummy_output.fd())
  defer source.close()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      for char in "\u{1B}[200~hello\u{1B}[201~" {
        source.read_key_record(win32_test_key_record(char))
      }
    }
    match source.read_decoded_input_event(50) {
      Input(Paste(text)) => @debug.assert_eq(text, "hello")
      _ => fail("expected bracketed paste event")
    }
  }
}
