///|
#cfg(all(target="native", not(platform="windows")))
let _windows_internal_import_anchor : Unit = {
  ignore(@win32.EventReader::new)
  ignore(@win32.InputRecord::parse)
}

///|
#cfg(target="wasm")
let _windows_record_import_anchor : Unit = ignore(@win32.InputRecord::parse)

///|
#cfg(target="native")
let _sidecar_import_anchor : Unit = ignore(@sidecar.SIDECAR_ENV)
