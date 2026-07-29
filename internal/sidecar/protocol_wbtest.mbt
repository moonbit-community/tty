///|
test "response decoding follows the request shape" {
  debug_inspect(
    Response::decode(
      IsATty(which=0),
      id=42,
      b"\x00\x2A\x00\x00\x00\x01\x00",
      b"\x01",
    ),
    content="Some(IsATty(true))",
  )
  debug_inspect(
    Response::decode(
      EnterRawMode(input=0, output=1),
      id=2,
      b"\x00\x02\x00\x00\x00\x00\x00",
      b"",
    ),
    content="Some(Acknowledged)",
  )
  debug_inspect(
    Response::decode(
      WinSize(which=1),
      id=3,
      b"\x00\x03\x00\x00\x00\x08\x00",
      b"\x28\x00\x00\x00\x50\x00\x00\x00",
    ),
    content="Some(WinSize(rows=40, cols=80))",
  )
  debug_inspect(
    Response::decode(
      Watch(enable=true),
      id=4,
      b"\x00\x04\x00\x00\x00\x00\x00",
      b"",
    ),
    content="Some(Acknowledged)",
  )
  debug_inspect(
    Response::decode(
      Shutdown,
      id=5,
      b"\x01\x05\x00\x00\x00\x04\x00",
      b"\x16\x00\x00\x00",
    ),
    content="Some(Error(errno=22))",
  )
}

///|
test "response decoding rejects protocol violations" {
  // Event frame on the control connection.
  debug_inspect(
    Response::decode(Shutdown, id=1, b"\x02\x00\x00\x00\x00\x00\x00", b""),
    content="None",
  )
  // Request id mismatch.
  debug_inspect(
    Response::decode(Shutdown, id=1, b"\x00\x09\x00\x00\x00\x00\x00", b""),
    content="None",
  )
  // Payload shape not matching the request.
  debug_inspect(
    Response::decode(
      WinSize(which=1),
      id=6,
      b"\x00\x06\x00\x00\x00\x01\x00",
      b"\x01",
    ),
    content="None",
  )
}
