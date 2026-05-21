///|
#warnings("-7")
#cfg(not(platform="windows"))
priv struct SigwinchWatcher {
  read : @async/pipe.PipeRead
  write : @async/pipe.PipeWrite
}

///|
#cfg(not(platform="windows"))
let global_sigwinch_watcher : Ref[SigwinchWatcher?] = Ref(None)

///|
#cfg(not(platform="windows"))
fn sigwinch_watcher() -> SigwinchWatcher raise {
  guard global_sigwinch_watcher.val is Some(watcher) else {
    let (read, write) = @async/pipe.pipe()
    if install_sigwinch_handler(write.fd()) < 0 {
      read.close()
      write.close()
      @os_error.check_errno("install SIGWINCH handler")
    }
    let watcher = SigwinchWatcher::{ read, write }
    global_sigwinch_watcher.val = Some(watcher)
    watcher
  }
  watcher
}

///|
#cfg(not(platform="windows"))
async fn SigwinchWatcher::wait(self : SigwinchWatcher) -> Unit {
  let buf = FixedArray::make(64, b'\x00')
  ignore(self.read.read(buf, max_len=buf.length()))
  // Drain with raw nonblocking read semantics. moonbitlang/async Reader APIs,
  // including read and read_some, wait for readiness after EAGAIN instead of
  // exposing "empty for now"; resize coalescing must stop at that boundary.
  drain_sigwinch_pipe(self.read.fd())
}

///|
#cfg(not(platform="windows"))
async fn Tty::read_resize_event(self : Self) -> Event {
  let watcher = sigwinch_watcher()
  for ;; {
    watcher.wait()
    try self.window_size() catch {
      _ => ()
    } noraise {
      size => return Resize(size)
    }
  }
}

///|
#cfg(not(platform="windows"))
async fn Tty::read_event_from_sources(
  self : Self,
  esc_timeout_ms : Int,
) -> Event {
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      group.return_immediately(self.read_decoded_input_event(esc_timeout_ms))
    }
    self.read_resize_event()
  }
}

///|
#cfg(not(platform="windows"))
extern "C" fn install_sigwinch_handler(fd : @async/types.Fd) -> Int = "moonbit_tty_install_sigwinch_handler"

///|
#cfg(not(platform="windows"))
extern "C" fn drain_sigwinch_pipe(fd : @async/types.Fd) -> Unit = "moonbit_tty_drain_sigwinch_pipe"
