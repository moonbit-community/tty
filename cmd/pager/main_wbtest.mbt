///|
test "split lines normalizes line endings" {
  inspect(split_lines("a\r\nb\rc\n").join("|"), content="a|b|c|")
}

///|
test "parse file args" {
  assert_true(parse_args_from([]).path == None)
  assert_true(parse_args_from(["README.md"]).path == Some("README.md"))
  assert_true(
    parse_args_from(["--file", "README.md"]).path == Some("README.md"),
  )
  assert_true(parse_args_from(["-f", "README.md"]).path == Some("README.md"))
}

///|
test "clamp offset keeps viewport in range" {
  let lines = ["a", "b", "c", "d", "e"]
  inspect(max_offset(lines, 2), content="3")
  inspect(clamp_offset(-1, lines, 2), content="0")
  inspect(clamp_offset(2, lines, 2), content="2")
  inspect(clamp_offset(9, lines, 2), content="3")
  inspect(clamp_offset(9, lines, 8), content="0")
}

///|
test "content fit detection" {
  let size : PagerSize = { rows: 4, cols: 80 }
  assert_true(content_fits(["a", "b", "c"], size))
  assert_false(content_fits(["a", "b", "c", "d"], size))
}

///|
test "fit line respects display width and graphemes" {
  inspect(fit_line("abcdef", 3), content="abc")
  inspect(fit_line("你好世界", 4), content="你好")
  inspect(
    fit_line("x👨‍👩‍👧‍👦y", 3),
    content="x👨‍👩‍👧‍👦",
  )
}

///|
test "sample content is scrollable on tall terminals" {
  assert_true(sample_lines().length() > 100)
}
