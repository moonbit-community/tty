///|
// Package imports are shared across target-specific files. The sidecar
// transport packages are only touched by the wasm backend files.
let _sidecar_transport_import_anchor : Unit = {
  ignore(@async/socket.Addr::parse)
  ignore(@async/process.hard_cancel)
  ignore(@sidecar.INPUT_RECORD_SIZE)
  ignore(@utf8.encode("", bom=false))
}
