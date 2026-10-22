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
    // A record is exactly one 20-byte INPUT_RECORD.
    let record = Bytes::make(20, b'r')
    events.write(b"\x84\x14\x00\x00\x00" + record)
    assert_true(conn.read_frame() is Some(Record(r)) && r == record)
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
/// A read cancelled between the header and the payload must not lose the
/// header: the decoder's escape timeout and the query timeouts do exactly
/// this.
async test "frame split by a cancelled read survives" {
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x81\x03\x00\x00\x00a")
    assert_true(@async.with_timeout_opt(50, () => conn.read_frame()) is None)
    events.write(b"bc")
    assert_true(conn.read_frame() is Some(Input(b"abc")))
    events.write(b"\x82\x04\x00\x00\x00\x18\x00")
    assert_true(@async.with_timeout_opt(50, () => conn.read_frame()) is None)
    events.write(b"\x50\x00")
    debug_inspect(conn.read_frame(), content="Some(Resize(rows=24, cols=80))")
  })
}

///|
async test "large writes are split into frames the sidecar accepts" {
  with_fake_sidecar((conn, _, commands) => {
    let data = Bytes::make(@sidecar.MAX_WRITE * 2 + 1, b'x')
    // The data is larger than a pipe buffer, so write and read concurrently.
    @async.with_task_group(group => {
      group.spawn_bg(() => conn.write(data))
      for expected in [@sidecar.MAX_WRITE, @sidecar.MAX_WRITE, 1] {
        let header = commands.read_exactly(5)
        guard header is [b'\x02', u32le(len)] else { fail("bad frame header") }
        assert_eq(len.reinterpret_as_int(), expected)
        assert_eq(commands.read_exactly(expected).length(), expected)
      }
    })
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
/// Once a send fails the sidecar may be waiting for the rest of a frame, so
/// the connection refuses to send anything else.
async test "a failed send poisons the connection" {
  with_fake_sidecar((conn, _, commands) => {
    commands.close()
    try conn.set_raw(true) catch {
      @sidecar.ProtocolError(_) => fail("the first failure is the OS error")
      _ => ()
    } noraise {
      _ => fail("expected the send to fail without a reader")
    }
    try conn.set_raw(false) catch {
      @sidecar.ProtocolError(_) => ()
      error => fail("expected a protocol error, got \{Repr(error)}")
    } noraise {
      _ => fail("expected the connection to be poisoned")
    }
  })
}

///|
async test "fixed-size frames must have their exact size" {
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x84\x02\x00\x00\x00ab")
    expect_protocol_error(conn)
  })
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x82\x05\x00\x00\x00\x18\x00\x50\x00\x00")
    expect_protocol_error(conn)
  })
  with_fake_sidecar((conn, events, _) => {
    events.write(b"\x80\x09\x00\x00\x00\x01\x00\x00\x00\x18\x00\x50\x00\x07")
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
