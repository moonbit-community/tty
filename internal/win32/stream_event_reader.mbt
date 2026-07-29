///|
/// Console event reader fed by the sidecar's raw `INPUT_RECORD` stream
/// (wasm backend). Same record routing as the native `EventReader`; only
/// the record source differs.
struct StreamEventReader {
  router : RecordRouter
  records : @sidecar.EventStream
}

///|
pub fn StreamEventReader::StreamEventReader(
  records : @sidecar.EventStream,
) -> StreamEventReader {
  { router: RecordRouter(), records }
}

///|
pub fn StreamEventReader::close(self : StreamEventReader) -> Unit {
  self.router.close()
}

///|
pub async fn StreamEventReader::read_event(
  self : StreamEventReader,
  esc_timeout_ms? : Int = 50,
) -> Event? {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.pump_records() }
    self.router.read_input_event(esc_timeout_ms)
  }
}

///|
pub async fn StreamEventReader::read_internal_event(
  self : StreamEventReader,
  esc_timeout_ms? : Int = 50,
) -> @input.Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => { self.pump_records() }
    self.router.decoder.read_event(esc_timeout_ms~)
  }
}

///|
/// Feed sidecar events into the router. Record batches are routed whole
/// between suspension points, so cancellation never tears a record apart.
async fn StreamEventReader::pump_records(self : StreamEventReader) -> Unit {
  for ;; {
    match self.records.next() {
      InputRecords(records~) => {
        let mut offset = 0
        while offset < records.length() {
          self.router.route(
            InputRecord::parse(
              records[offset:offset + @sidecar.INPUT_RECORD_SIZE],
            ),
          )
          offset += @sidecar.INPUT_RECORD_SIZE
        }
      }
      // Unix-only on the wire today; treat a stray resize as the record
      // equivalent so behavior stays sensible if a future sidecar sends it.
      Resize(..) => self.router.route(WindowBufferSize({ x: 0, y: 0 }))
    }
  }
}
