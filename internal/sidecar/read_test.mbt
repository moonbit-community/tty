///|
async test "response read frames a reply out of a byte stream" {
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"\x00\x2A\x00\x00\x00\x01\x00\x01")
  })
  defer reader.close()
  let response = @sidecar.Response::read(
    reader as &@async/io.Reader,
    IsATty(which=0),
    id=42,
  )
  debug_inspect(response, content="IsATty(true)")
}

///|
async test "response read splits consecutive replies" {
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"\x00\x01\x00\x00\x00\x00\x00")
    writer.write(b"\x01\x02\x00\x00\x00\x04\x00\x16\x00\x00\x00")
  })
  defer reader.close()
  let reader = reader as &@async/io.Reader
  debug_inspect(
    @sidecar.Response::read(reader, Watch(enable=true), id=1),
    content="Acknowledged",
  )
  debug_inspect(
    @sidecar.Response::read(reader, Shutdown, id=2),
    content="Error(errno=22)",
  )
}

///|
async test "response read rejects unknown frame kinds" {
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"\x07\x00\x00\x00\x00\x00\x00")
  })
  defer reader.close()
  try
    @sidecar.Response::read(reader as &@async/io.Reader, Shutdown, id=1)
  catch {
    @sidecar.ProtocolViolation => ()
    error => raise error
  } noraise {
    response => fail("expected protocol violation, got \{Repr(response)}")
  }
}

///|
async test "event stream delivers resizes and skips unknown codes" {
  let reader = @async/io.MemoryReader(writer => {
    // An unknown event (code 9) followed by a resize event, split across
    // writes to exercise reassembly.
    writer.write(b"\x02\x00\x00\x00\x00\x01\x00\x09")
    writer.write(b"\x02\x00\x00\x00\x00\x09\x00\x01\x28")
    writer.write(b"\x00\x00\x00\x50\x00\x00\x00")
  })
  defer reader.close()
  let stream = @sidecar.EventStream(reader as &@async/io.Reader)
  debug_inspect(stream.next(), content="Resize(rows=40, cols=80)")
}

///|
async test "event stream delivers whole input record batches" {
  let records = Bytes::make(40, b'\x41')
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"\x02\x00\x00\x00\x00\x29\x00\x02")
    writer.write(records)
  })
  defer reader.close()
  let stream = @sidecar.EventStream(reader as &@async/io.Reader)
  guard stream.next() is InputRecords(records=received) else {
    fail("expected an input record batch")
  }
  assert_eq(received, records)
}

///|
async test "event stream rejects torn record batches" {
  let reader = @async/io.MemoryReader(writer => {
    // 22 payload bytes: event code 2 plus one record byte too many.
    writer.write(b"\x02\x00\x00\x00\x00\x16\x00\x02")
    writer.write(Bytes::make(21, b'\x41'))
  })
  defer reader.close()
  let stream = @sidecar.EventStream(reader as &@async/io.Reader)
  try stream.next() catch {
    @sidecar.ProtocolViolation => ()
    error => raise error
  } noraise {
    event => fail("expected protocol violation, got \{Repr(event)}")
  }
}

///|
async test "handshake read validates magic and token" {
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"MTTC\x01\x00\x04\x00beef")
  })
  defer reader.close()
  @sidecar.read_handshake(
    reader as &@async/io.Reader,
    magic=@sidecar.MAGIC_CONTROL,
    token=b"beef",
  )
}

///|
async test "handshake read rejects a wrong token" {
  let reader = @async/io.MemoryReader(writer => {
    writer.write(b"MTTC\x01\x00\x04\x00beef")
  })
  defer reader.close()
  try
    @sidecar.read_handshake(
      reader as &@async/io.Reader,
      magic=@sidecar.MAGIC_CONTROL,
      token=b"dead",
    )
  catch {
    @sidecar.ProtocolViolation => ()
    error => raise error
  } noraise {
    _ => fail("expected protocol violation for a mismatched token")
  }
}

///|
async test "event stream survives cancelled waits over a pipe" {
  let (read, write) = @async/pipe.pipe()
  defer {
    read.close()
    write.close()
  }
  let stream = @sidecar.EventStream(read as &@async/io.Reader)
  // Deliver only part of a resize frame, let a waiter get cancelled
  // mid-frame, then complete the frame: no byte may be lost or re-read.
  write.write(b"\x02\x00\x00\x00\x00\x09\x00\x01")
  match @async.with_timeout_opt(10, () => stream.next()) {
    None => ()
    Some(_) => fail("expected the partial frame to time out")
  }
  write.write(b"\x28\x00\x00\x00\x50\x00\x00\x00")
  debug_inspect(stream.next(), content="Resize(rows=40, cols=80)")
}
