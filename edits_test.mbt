///|
test "apply_edits handles multiple unsorted spans while preserving BOM and CRLF" {
  let source = "\uFEFF// 中文 😀\r\nname = \"acme/app\"\r\nversion = \"0.1.0\"\r\nimport {\r\n  \"acme/dep@1.0.0\",\r\n}\r\n"
  let doc = @moon-manifest.parse(Mod, source)
  let version_span = doc.string_field("version").unwrap().span
  let dep_span = doc.dependencies()[0].span
  let updated = doc.apply_edits([
    { span: dep_span, replacement: "\"acme/dep@1.1.0\"", },
    { span: version_span, replacement: "\"0.2.0\"", },
  ])
  assert_eq(
    @utf8.decode_lossy(updated),
    "\uFEFF// 中文 😀\r\nname = \"acme/app\"\r\nversion = \"0.2.0\"\r\nimport {\r\n  \"acme/dep@1.1.0\",\r\n}\r\n",
  )
}

///|
test "replace_span rejects out of bounds spans" {
  let doc = @moon-manifest.parse(Mod, "name = \"acme/app\"\n")
  try doc.replace_span({ start: 0, end: 999, }, "\"x\"") catch {
    err =>
      debug_inspect(
        err,
        content=(
          #|OutOfBounds(span={ start: 0, end: 999 }, source_len=18)
        ),
      )
  } noraise {
    _ => fail("expected OutOfBounds")
  }
}

///|
test "apply_edits rejects overlapping spans" {
  let doc = @moon-manifest.parse(Mod, "name = \"acme/app\"\n")
  try
    doc.apply_edits([
      { span: { start: 0, end: 6, }, replacement: "a", },
      { span: { start: 4, end: 8, }, replacement: "b", },
    ])
  catch {
    err =>
      debug_inspect(
        err,
        content=(
          #|OverlappingSpans(
          #|  first={ start: 0, end: 6 },
          #|  second={ start: 4, end: 8 },
          #|)
        ),
      )
  } noraise {
    _ => fail("expected OverlappingSpans")
  }
}
