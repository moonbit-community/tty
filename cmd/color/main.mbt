///|
async fn write(text : String) -> Unit {
  @tty.stdout.write(text)
}

///|
async fn write_bytes(bytes : Bytes) -> Unit {
  @tty.stdout.write(bytes)
}

///|
async fn writeln(text : String) -> Unit {
  write(text)
  write("\r\n")
}

///|
fn pad_right(text : String, width : Int) -> String {
  if text.length() >= width {
    text
  } else {
    text + String::make(width - text.length(), ' ')
  }
}

///|
fn basic_color(index : Int) -> @tty_color.BasicColor {
  match index {
    0 => @tty_color.Black
    1 => @tty_color.Red
    2 => @tty_color.Green
    3 => @tty_color.Yellow
    4 => @tty_color.Blue
    5 => @tty_color.Magenta
    6 => @tty_color.Cyan
    7 => @tty_color.White
    8 => @tty_color.BrightBlack
    9 => @tty_color.BrightRed
    10 => @tty_color.BrightGreen
    11 => @tty_color.BrightYellow
    12 => @tty_color.BrightBlue
    13 => @tty_color.BrightMagenta
    14 => @tty_color.BrightCyan
    _ => @tty_color.BrightWhite
  }
}

///|
fn basic_name(index : Int) -> String {
  match index {
    0 => "black"
    1 => "red"
    2 => "green"
    3 => "yellow"
    4 => "blue"
    5 => "magenta"
    6 => "cyan"
    7 => "white"
    8 => "bright black"
    9 => "bright red"
    10 => "bright green"
    11 => "bright yellow"
    12 => "bright blue"
    13 => "bright magenta"
    14 => "bright cyan"
    _ => "bright white"
  }
}

///|
fn light_basic_background(index : Int) -> Bool {
  index == 3 ||
  index == 6 ||
  index == 7 ||
  index == 10 ||
  index == 11 ||
  index == 14 ||
  index == 15
}

///|
async fn write_basic_foregrounds() -> Unit {
  writeln("ANSI 16 foreground")
  for i in 0..<16 {
    write_bytes(@tty_color.foreground(@tty_color.Basic(basic_color(i))))
    write(pad_right(basic_name(i), 15))
    write_bytes(@tty_color.reset_foreground)
    if i == 7 || i == 15 {
      writeln("")
    } else {
      write(" ")
    }
  }
}

///|
async fn write_basic_backgrounds() -> Unit {
  writeln("ANSI 16 background")
  for i in 0..<16 {
    let foreground = if light_basic_background(i) {
      @tty_color.Basic(@tty_color.Black)
    } else {
      @tty_color.Basic(@tty_color.White)
    }
    write_bytes(@tty_color.background(@tty_color.Basic(basic_color(i))))
    write_bytes(@tty_color.foreground(foreground))
    write(" " + pad_right(basic_name(i), 14))
    write_bytes(@tty_color.reset_style)
    if i == 7 || i == 15 {
      writeln("")
    } else {
      write(" ")
    }
  }
}

///|
async fn write_index_swatch(index : Int) -> Unit {
  write_bytes(@tty_color.background(@tty_color.Indexed(index)))
  write("  ")
  write_bytes(@tty_color.reset_style)
}

///|
async fn write_256_colors() -> Unit {
  writeln("Indexed 0..15")
  for i in 0..<16 {
    write_index_swatch(i)
  }
  writeln("")
  writeln("Indexed 16..231 color cube")
  for red in 0..<6 {
    writeln("red=\{red}")
    for green in 0..<6 {
      for blue in 0..<6 {
        write_index_swatch(16 + red * 36 + green * 6 + blue)
      }
      writeln("")
    }
  }
  writeln("Indexed 232..255 grayscale")
  for i in 232..<256 {
    write_index_swatch(i)
  }
  writeln("")
}

///|
async fn write_truecolor_gradient() -> Unit {
  writeln("Truecolor RGB gradients")
  for row in 0..<3 {
    for col in 0..<64 {
      let value = col * 255 / 63
      let color = match row {
        0 => @tty_color.Rgb(value, 48, 255 - value)
        1 => @tty_color.Rgb(255 - value, value, 64)
        _ => @tty_color.Rgb(64, 255 - value, value)
      }
      write_bytes(@tty_color.background(color))
      write(" ")
    }
    write_bytes(@tty_color.reset_style)
    writeln("")
  }
}

///|
async fn main {
  writeln("tty color specimen")
  writeln("")
  write_basic_foregrounds()
  writeln("")
  write_basic_backgrounds()
  writeln("")
  write_256_colors()
  writeln("")
  write_truecolor_gradient()
  write_bytes(@tty_color.reset_style)
}
