///|
test "latex document wraps formula" {
  let document = latex_document("\\alpha^2 + \\beta")
  inspect(document.contains("\\usepackage{amsmath}"), content="true")
  inspect(
    document.contains("$\\displaystyle \\alpha^2 + \\beta$"),
    content="true",
  )
  inspect(document.contains("\\["), content="false")
}

///|
test "renderer command arguments" {
  inspect(
    tectonic_args("/tmp/demo").join("|"),
    content="--outdir|/tmp/demo|/tmp/demo/formula.tex",
  )
  inspect(
    pdflatex_args("/tmp/demo").join("|"),
    content="-interaction=nonstopmode|-halt-on-error|-output-directory|/tmp/demo|/tmp/demo/formula.tex",
  )
  inspect(
    pdftocairo_args("/tmp/demo").join("|"),
    content="-png|-singlefile|-r|600|/tmp/demo/formula.pdf|/tmp/demo/formula",
  )
}

///|
test "ctrl c exits" {
  inspect(
    is_exit_key(
      @tty/input.KeyEvent::new(
        Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
      ),
    ),
    content="true",
  )
  inspect(is_exit_key(@tty/input.KeyEvent::new(Char('q'))), content="false")
  inspect(
    is_exit_key(
      @tty/input.KeyEvent::new(
        Char('c'),
        modifiers=@tty/input.KeyModifiers::new(ctrl=true),
        kind=Release,
      ),
    ),
    content="false",
  )
}

///|
test "apply text key edits formula parts" {
  let parts : Array[String] = []
  ignore(apply_text_key(parts, @tty/input.KeyEvent::new(Char('x'), text="x")))
  ignore(apply_text_key(parts, @tty/input.KeyEvent::new(Char('^'), text="^")))
  ignore(apply_text_key(parts, @tty/input.KeyEvent::new(Char('2'), text="2")))
  inspect(formula_text(parts), content="x^2")
  ignore(apply_text_key(parts, @tty/input.KeyEvent::new(Backspace)))
  inspect(formula_text(parts), content="x^")
}
