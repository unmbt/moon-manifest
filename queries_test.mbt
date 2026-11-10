///|
test "located imports and fields preserve Unicode and CRLF" {
  let source = "// 中文 😀\r\nname = \"acme/test\"\r\nversion = \"0.1.0\"\r\nprivate = true\r\nimport { \"acme/lib@0.2.0\" }\r\n"
  let doc = @moon-manifest.parse(Mod, source)
  assert_eq(doc.diagnostics.length(), 0)
  assert_true(doc.is_private())
  let name = doc.string_field("name").unwrap()
  assert_eq(
    @utf8.decode_lossy(doc.source[name.span.start:name.span.end]),
    "\"acme/test\"",
  )
  let dep = doc.dependencies()[0]
  assert_eq(dep.name, "acme/lib")
  assert_eq(dep.version, "0.2.0")
  assert_eq(
    @utf8.decode_lossy(doc.source[dep.span.start:dep.span.end]),
    "\"acme/lib@0.2.0\"",
  )
  assert_eq(@utf8.decode_lossy(doc.source), source)
}

///|
test "duplicate and complex imports are diagnosed instead of dropped" {
  for
    source in [
      "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\", \"acme/lib@0.2.0\" }",
      "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\" @alias }", "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\" } for \"test\"",
      "name = \"acme/test\"\nversion = \"0.1.0\"\nversion = \"0.2.0\"",
    ] {
    assert_true(!@moon-manifest.parse(Mod, source).diagnostics.is_empty())
  }
}

///|
test "member locations and missing versions" {
  let doc = @moon-manifest.parse(Work, "members = [\"./a\", \"./b\"]")
  assert_eq(doc.member_entries().map(x => x.value), ["./a", "./b"])
  assert_eq(@moon-manifest.parse(Mod, "name = \"acme/test\"").version(), None)
}

///|
test "BOM and same-line Unicode preserve byte spans" {
  let source = "\uFEFFdescription = \"😀 中文\"\r\nname = \"acme/test\"\r\nversion = \"0.1.0\""
  let doc = @moon-manifest.parse(Mod, source)
  assert_eq(doc.diagnostics.length(), 0)
  let entry = doc.string_field("name").unwrap()
  assert_eq(
    @utf8.decode_lossy(doc.source[entry.span.start:entry.span.end]),
    "\"acme/test\"",
  )
  assert_eq(@utf8.decode_lossy(doc.source), source)
}
