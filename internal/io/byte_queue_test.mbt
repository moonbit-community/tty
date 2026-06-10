///|
async test "byte queue drains queued bytes" {
  let queue = ByteQueue::new()
  queue.put_byte(b'a')
  queue.put_byte(b'b')
  queue.put_byte(b'c')
  let dst = FixedArray::make(4, b'\x00')
  let n = queue.read(dst, max_len=4)
  @debug.assert_eq(n, 3)
  @debug.assert_eq(dst.unsafe_reinterpret_as_bytes()[:n].to_owned(), b"abc")
}

///|
async test "byte queue waits for first byte" {
  let queue = ByteQueue::new()
  let dst = FixedArray::make(2, b'\x00')
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(10)
      queue.put_byte(b'x')
    }
    let n = queue.read(dst, max_len=2)
    @debug.assert_eq(n, 1)
    @debug.assert_eq(dst.unsafe_reinterpret_as_bytes()[:n].to_owned(), b"x")
  }
}

///|
async test "byte queue reports eof when closed" {
  let queue = ByteQueue::new()
  queue.close()
  let dst = FixedArray::make(1, b'\x00')
  @debug.assert_eq(queue.read(dst, max_len=1), 0)
}

///|
async test "byte queue writes data" {
  let queue = ByteQueue::new()
  queue.put_data("ab")
  queue.put_data(b"cd")
  let dst = FixedArray::make(8, b'\x00')
  let n = queue.read(dst, max_len=8)
  @debug.assert_eq(n, 4)
  @debug.assert_eq(dst.unsafe_reinterpret_as_bytes()[:n].to_owned(), b"abcd")
}
