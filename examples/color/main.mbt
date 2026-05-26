///|
async fn write(tty : @tty.Tty, text : String) -> Unit {
  tty.write(text)
}

///|
async fn writeln(tty : @tty.Tty, text : String) -> Unit {
  write(tty, text)
  write(tty, "\r\n")
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
    0 => Black
    1 => Red
    2 => Green
    3 => Yellow
    4 => Blue
    5 => Magenta
    6 => Cyan
    7 => White
    8 => BrightBlack
    9 => BrightRed
    10 => BrightGreen
    11 => BrightYellow
    12 => BrightBlue
    13 => BrightMagenta
    14 => BrightCyan
    _ => BrightWhite
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
async fn write_basic_foregrounds(tty : @tty.Tty) -> Unit {
  writeln(tty, "ANSI 16 foreground")
  for i in 0..<16 {
    tty.set_foreground(Basic(basic_color(i)))
    write(tty, pad_right(basic_name(i), 15))
    tty.reset_foreground()
    if i == 7 || i == 15 {
      writeln(tty, "")
    } else {
      write(tty, " ")
    }
  }
}

///|
async fn write_basic_backgrounds(tty : @tty.Tty) -> Unit {
  writeln(tty, "ANSI 16 background")
  for i in 0..<16 {
    let foreground = if light_basic_background(i) {
      @tty_color.Basic(Black)
    } else {
      Basic(White)
    }
    tty.set_background(Basic(basic_color(i)))
    tty.set_foreground(foreground)
    write(tty, " " + pad_right(basic_name(i), 14))
    tty.reset_style()
    if i == 7 || i == 15 {
      writeln(tty, "")
    } else {
      write(tty, " ")
    }
  }
}

///|
async fn write_index_swatch(tty : @tty.Tty, index : Int) -> Unit {
  tty.set_background(Indexed(index))
  write(tty, "  ")
  tty.reset_style()
}

///|
async fn write_256_colors(tty : @tty.Tty) -> Unit {
  writeln(tty, "Indexed 0..15")
  for i in 0..<16 {
    write_index_swatch(tty, i)
  }
  writeln(tty, "")
  writeln(tty, "Indexed 16..231 color cube")
  for red in 0..<6 {
    writeln(tty, "red=\{red}")
    for green in 0..<6 {
      for blue in 0..<6 {
        write_index_swatch(tty, 16 + red * 36 + green * 6 + blue)
      }
      writeln(tty, "")
    }
  }
  writeln(tty, "Indexed 232..255 grayscale")
  for i in 232..<256 {
    write_index_swatch(tty, i)
  }
  writeln(tty, "")
}

///|
async fn write_truecolor_gradient(tty : @tty.Tty) -> Unit {
  writeln(tty, "Truecolor RGB gradients")
  for row in 0..<3 {
    for col in 0..<64 {
      let value = col * 255 / 63
      let color = match row {
        0 => @tty_color.Rgb(value, 48, 255 - value)
        1 => Rgb(255 - value, value, 64)
        _ => Rgb(64, 255 - value, value)
      }
      tty.set_background(color)
      write(tty, " ")
    }
    tty.reset_style()
    writeln(tty, "")
  }
}

///|
async fn write_attributes(tty : @tty.Tty) -> Unit {
  writeln(tty, "SGR attributes")
  tty.bold()
  write(tty, "bold")
  tty.reset_bold()
  write(tty, " ")
  tty.italic()
  write(tty, "italic")
  tty.reset_italic()
  write(tty, " ")
  tty.underline()
  write(tty, "underline")
  tty.reset_underline()
  write(tty, " ")
  tty.reverse()
  write(tty, "reverse")
  tty.reset_reverse()
  writeln(tty, "")
}

///|
async fn main {
  let tty = @tty.Tty::stdio()
  writeln(tty, "tty color and style specimen")
  writeln(tty, "")
  write_attributes(tty)
  writeln(tty, "")
  write_basic_foregrounds(tty)
  writeln(tty, "")
  write_basic_backgrounds(tty)
  writeln(tty, "")
  write_256_colors(tty)
  writeln(tty, "")
  write_truecolor_gradient(tty)
  tty.reset_style()
}
