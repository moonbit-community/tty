///|
#cfg(not(platform="windows"))
let _windows_internal_import_anchor : Unit = {
  ignore(@win32.EventReader::new)
  ignore(@win32.InputRecord::parse)
}
