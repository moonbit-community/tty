///|
/// Smoke tests shared between the native and wasm targets: construction,
/// write path, identification, and input decoding over plain pipes.
async test "tty over pipes writes styled output" {
  let red : @color.Color = Basic(Red)
  let (input_read, input_write) = @async/pipe.pipe()
  let (output_read, output_write) = @async/pipe.pipe()
  let tty = @tty.Tty::new(input_read, output_write)
  tty.write_string("plain-")
  tty.set_foreground(red)
  tty.reset_foreground()
  tty.close()
  input_write.close()
  let output = output_read.read_all()
  output_read.close()
  @debug.assert_eq(output.binary(), b"plain-\x1b[31m\x1b[39m")
}

///|
async test "tty pipe input decodes key events" {
  let (input_read, input_write) = @async/pipe.pipe()
  let (output_read, output_write) = @async/pipe.pipe()
  input_write.write(b"a")
  let tty = @tty.Tty::new(input_read, output_write)
  match tty.read_event() {
    Input(event) =>
      @debug.assert_eq(
        event,
        Key(@public_input.KeyEvent::new(Char('a'), text="a")),
      )
    Resize(_) => fail("expected key input")
  }
  tty.close()
  input_write.close()
  output_read.close()
}

///|
async test "isatty is false for pipes" {
  let (read, write) = @async/pipe.pipe()
  defer {
    read.close()
    write.close()
  }
  assert_false(@tty.isatty(read))
  assert_false(@tty.isatty(write))
}

///|
async test "stdio tty constructs and closes" {
  let tty = @tty.Tty::new(@async/stdio.stdin, @async/stdio.stdout)
  tty.close()
}
