///|
#cfg(not(platform="windows"))
let _windows_internal_import_anchor : Unit = {
  ignore(@internal_io.ByteQueue::new)
  ignore(@win32.InputRecord::parse)
}
