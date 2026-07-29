///|
// Package imports are shared across target-specific files. The sidecar
// protocol and client packages are only touched by the wasm backend files.
let _sidecar_import_anchor : Unit = {
  ignore(@sidecar.INPUT_RECORD_SIZE)
  ignore(@client.stdio_slot_or_invalid)
}
