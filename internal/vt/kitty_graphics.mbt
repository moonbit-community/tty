///|
pub let kitty_graphics_query_image_id : Int = 2147483647

///|
const KittyGraphicsRawChunkBytes : Int = 3072

///|
pub let query_kitty_graphics_support : Bytes = bytes_from_buffer(
  64, write_query_kitty_graphics_support,
)

///|
pub fn write_query_kitty_graphics_support(buf : @buffer.Buffer) -> Unit {
  buf.write_bytes(b"\x1b_Gi=")
  write_decimal(buf, kitty_graphics_query_image_id)
  buf.write_bytes(b",s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\")
}

///|
pub fn display_kitty_png(
  png : BytesView,
  image_id? : Int,
  columns? : Int,
  rows? : Int,
) -> Bytes {
  let size_hint = png.length() * 4 / 3 + 128
  bytes_from_buffer(size_hint, buf => {
    write_display_kitty_png(buf, png, image_id?, columns?, rows?)
  })
}

///|
pub fn write_display_kitty_png(
  buf : @buffer.Buffer,
  png : BytesView,
  image_id? : Int,
  columns? : Int,
  rows? : Int,
) -> Unit {
  if png.length() == 0 {
    write_display_kitty_png_chunk(
      buf,
      png,
      first=true,
      more=false,
      image_id?,
      columns?,
      rows?,
    )
    return
  }
  let mut offset = 0
  let mut first = true
  while offset < png.length() {
    let end = if offset + KittyGraphicsRawChunkBytes < png.length() {
      offset + KittyGraphicsRawChunkBytes
    } else {
      png.length()
    }
    write_display_kitty_png_chunk(
      buf,
      png[offset:end],
      first~,
      more=end < png.length(),
      image_id?,
      columns?,
      rows?,
    )
    offset = end
    first = false
  }
}

///|
fn write_display_kitty_png_chunk(
  buf : @buffer.Buffer,
  chunk : BytesView,
  first~ : Bool,
  more~ : Bool,
  image_id? : Int,
  columns? : Int,
  rows? : Int,
) -> Unit {
  buf.write_bytes(b"\x1b_G")
  if first {
    buf.write_bytes(b"a=T,f=100,t=d,q=1,m=")
  } else {
    buf.write_bytes(b"q=1,m=")
  }
  buf.write_byte(if more { b'1' } else { b'0' })
  if first {
    write_optional_positive_field(buf, b'i', image_id)
    write_optional_positive_field(buf, b'c', columns)
    write_optional_positive_field(buf, b'r', rows)
    // Keep terminal UI code from having to repair cursor position after images.
    buf.write_bytes(b",C=1")
  }
  buf.write_byte(b';')
  buf.write_string_utf8(@base64.encode(chunk, padding=false))
  buf.write_bytes(b"\x1b\\")
}

///|
fn write_optional_positive_field(
  buf : @buffer.Buffer,
  key : Byte,
  value : Int?,
) -> Unit {
  match value {
    Some(value) if value > 0 => {
      buf.write_byte(b',')
      buf.write_byte(key)
      buf.write_byte(b'=')
      write_decimal(buf, value)
    }
    _ => ()
  }
}
