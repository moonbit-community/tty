///|
// Package imports are shared with the wasm-only client files; reference
// them here so the native build of this package stays warning-free.
let _wasm_import_anchor : Unit = {
  ignore(@async.is_being_cancelled)
  ignore(@async/socket.Addr::parse)
  ignore(@async/process.hard_cancel)
  ignore(@utf8.encode("", bom=false))
  ignore(@sidecar.INPUT_RECORD_SIZE)
  ignore(@os_error.errno_ENOTDIR)
  ignore(@lock.Lock::new)
  ignore(Buffer())
}

///|
let _fs_import_anchor : @async/fs.File? = None

///|
let _io_import_anchor : &@async/io.Reader? = None

///|
let _win32_import_anchor : @win32.Event? = None
