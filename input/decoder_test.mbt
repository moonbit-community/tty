///|
async fn with_input(bytes : Bytes, f : async (@io.PipeRead) -> Unit) -> Unit {
  @async.with_task_group() <| group => {
    let (reader, writer) = @io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(bytes)
    }
    f(reader)
    reader.close()
  }
}

///|
async fn with_delayed_input(
  first : Bytes,
  second : Bytes,
  delay : Int,
  f : async (@io.PipeRead) -> Unit,
) -> Unit {
  @async.with_task_group() <| group => {
    let (reader, writer) = @io.pipe()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(first)
      @async.sleep(delay)
      writer.write(second)
    }
    f(reader)
    reader.close()
  }
}

///|
async test "decode printable ascii" {
  with_input(b"a", reader => {
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}

///|
async test "flush escape key" {
  with_delayed_input(b"\x1b", b"", 50, reader => {
    @debug.assert_eq(
      @input.read_event(reader, esc_timeout=10),
      @input.Key(@input.KeyEvent::new(@input.Escape)),
    )
  })
}

///|
async test "decode split csi arrow" {
  with_delayed_input(b"\x1b[", b"A", 5, reader => {
    @debug.assert_eq(
      @input.read_event(reader, esc_timeout=50),
      @input.Key(@input.KeyEvent::new(@input.Up)),
    )
  })
}

///|
async test "decode csi tilde key" {
  with_input(b"\x1b[3~", reader => {
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(@input.KeyEvent::new(@input.Delete)),
    )
  })
}

///|
async test "decode alt key" {
  with_input(b"\x1bx", reader => {
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(
        @input.KeyEvent::new(
          @input.Char('x'),
          modifiers=@input.KeyModifiers::new(alt=true),
        ),
      ),
    )
  })
}

///|
async test "flush incomplete csi as unknown" {
  with_delayed_input(b"\x1b[12;", b"", 50, reader => {
    @debug.assert_eq(
      @input.read_event(reader, esc_timeout=10),
      @input.Unknown(b"\x1b[12;"),
    )
  })
}

///|
async test "decode multiple events with repeated calls" {
  with_input(b"a\r", reader => {
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(@input.KeyEvent::new(@input.Enter)),
    )
  })
}

///|
async test "decode unsupported csi as unknown and leaves following bytes buffered" {
  with_input(b"\x1b[999~a", reader => {
    @debug.assert_eq(@input.read_event(reader), @input.Unknown(b"\x1b[999~"))
    @debug.assert_eq(
      @input.read_event(reader),
      @input.Key(@input.KeyEvent::new(@input.Char('a'), text="a")),
    )
  })
}
