///|
#warnings("-14")
struct ByteQueue {
  queue : @async.Queue[Byte]
  read_buf : @async/io.ReaderBuffer
}

///|
#warnings("-14")
pub fn ByteQueue::new() -> ByteQueue {
  { queue: Queue(kind=Unbounded), read_buf: @async/io.ReaderBuffer::new() }
}

///|
pub fn ByteQueue::close(self : ByteQueue) -> Unit {
  self.queue.close(error=@async/io.ReaderClosed, clear=true)
}

///|
pub fn ByteQueue::put_byte(self : ByteQueue, byte : Byte) -> Unit {
  guard (try! self.queue.try_put(byte))
}

///|
pub fn ByteQueue::put_data(self : ByteQueue, data : &@async/io.Data) -> Unit {
  for byte in data.binary() {
    self.put_byte(byte)
  }
}

///|
pub impl @async/io.Reader for ByteQueue with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @async/io.Reader for ByteQueue with fn _direct_read(
  self,
  dst,
  offset~,
  max_len~,
) {
  if max_len <= 0 {
    return 0
  }
  let first = try self.queue.get() catch {
    @async/io.ReaderClosed => return 0
    error => raise error
  } noraise {
    byte => byte
  }
  dst[offset] = first
  let mut len = 1
  while len < max_len {
    let next = try self.queue.try_get() catch {
      @async/io.ReaderClosed => None
      error => raise error
    } noraise {
      byte => byte
    }
    if next is Some(byte) {
      dst[offset + len] = byte
      len += 1
    } else {
      break
    }
  }
  len
}
