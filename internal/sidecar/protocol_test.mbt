///|
/// A `Connection` whose peer is a pair of pipes we drive by hand.
async fn with_fake_sidecar(
  f : async (@sidecar.Connection, @async/pipe.PipeWrite, @async/pipe.PipeRead) -> Unit,
) -> Unit {
  let (events_read, events_write) = @async/pipe.pipe()
  let (commands_read, commands_write) = @async/pipe.pipe()
  defer {
    events_read.close()
    events_write.close()
    commands_read.close()
    commands_write.close()
  }
  let conn = @sidecar.Connection::new(events_read, commands_write)
  f(conn, events_write, commands_read)
}

///|
async test "frames round trip" {
  with_fake_sidecar((conn, events, commands) => {
    events.write(b"\x80\x08\x00\x00\x00\x01\x00\x00\x00\x18\x00\x50\x00")
    debug_inspect(
      conn.read_frame(),
      content="Some(Hello(version=1, rows=24, cols=80))",
    )
    events.write(b"\x81\x03\x00\x00\x00abc")
    assert_true(conn.read_frame() is Some(Input(b"abc")))
    events.write(b"\x82\x04\x00\x00\x00\x1f\x00\x65\x00")
    debug_inspect(conn.read_frame(), content="Some(Resize(rows=31, cols=101))")
    events.write(b"\x83\x05\x00\x00\x00oops!")
    debug_inspect(conn.read_frame(), content="Some(Error(\"oops!\"))")
    conn.set_raw(true)
    conn.write(b"hi")
    assert_eq(
      commands.read_exactly(13),
      b"\x01\x01\x00\x00\x00\x01\x02\x02\x00\x00\x00hi",
    )
  })
}

///|
async test "eof and truncated frames" {
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x81\x05\x00\x00\x00ab")
    events.close()
    expect_protocol_error(conn)
  })
  with_fake_sidecar((conn, events, _) => {
    events.close()
    assert_true(conn.read_frame() is None)
  })
}

///|
async test "unknown tag is rejected" {
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x7f\x00\x00\x00\x00")
    expect_protocol_error(conn)
  })
}

///|
async fn expect_protocol_error(conn : @sidecar.Connection) -> Unit {
  try conn.read_frame() catch {
    @sidecar.ProtocolError(_) => ()
    e => raise e
  } noraise {
    frame => fail("expected a protocol error, got \{Repr(frame)}")
  }
}
