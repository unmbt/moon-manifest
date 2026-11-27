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
  assert_eq(doc.dependencies().length(), 1)
  let dep = doc.dependencies()[0]
  assert_eq(dep.name, "acme/lib")
  assert_eq(dep.version, "0.2.0")
  assert_eq(doc.dependency_version("acme/lib"), Some("0.2.0"))
  assert_eq(
    @utf8.decode_lossy(doc.source[dep.span.start:dep.span.end]),
    "\"acme/lib@0.2.0\"",
  )
  assert_eq(@utf8.decode_lossy(doc.source), source)
}

///|
test "duplicate, malformed, and complex imports are diagnosed instead of dropped" {
  let cases = [
    "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\", \"acme/lib@0.2.0\" }", "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\" @alias }",
    "name = \"acme/test\"\nimport { \"acme/lib@0.1.0\" } for \"test\"", "name = \"acme/test\"\nversion = \"0.1.0\"\nversion = \"0.2.0\"",
    "name = \"acme/test\"\nimport { \"acme/lib\" }", "name = \"acme/test\"\nimport { \"acme/lib@\" }",
    "name = \"acme/test\"\nimport { \"@0.1.0\" }",
  ]
  let diagnostics = cases.map(source => {
    @moon-manifest.parse(Mod, source).diagnostics
  })
  debug_inspect(
    diagnostics,
    content=(
      #|[
      #|  [{ message: "Duplicate dependency `acme/lib`", start: 46, end: 62 }],
      #|  [
      #|    {
      #|      message: "Unsupported module import: expected a plain module@version string",
      #|      start: 28,
      #|      end: 51,
      #|    },
      #|  ],
      #|  [
      #|    {
      #|      message: "Invalid configuration `test-import` in moon.mod file.",
      #|      start: 19,
      #|      end: 57,
      #|    },
      #|  ],
      #|  [
      #|    {
      #|      message: "Invalid configuration `version` in moon.mod file.",
      #|      start: 47,
      #|      end: 54,
      #|    },
      #|  ],
      #|  [
      #|    {
      #|      message: "Invalid module import `acme/lib`: expected a plain module@version string",
      #|      start: 28,
      #|      end: 38,
      #|    },
      #|  ],
      #|  [
      #|    {
      #|      message: "Invalid module import `acme/lib@`: expected a plain module@version string",
      #|      start: 28,
      #|      end: 39,
      #|    },
      #|  ],
      #|  [
      #|    {
      #|      message: "Invalid module import `@0.1.0`: expected a plain module@version string",
      #|      start: 28,
      #|      end: 36,
      #|    },
      #|  ],
      #|]
    ),
  )
}

///|
test "member locations and missing versions" {
  let doc = @moon-manifest.parse(Work, "members = [\"./a\", \"./b\"]")
  assert_eq(doc.member_entries().map(x => x.value), ["./a", "./b"])
  assert_eq(@moon-manifest.parse(Mod, "name = \"acme/test\"").version(), None)
}

///|
test "BOM and same-line Unicode preserve byte spans" {
  let source = "\uFEFFdescription = \"😀 中文\"\r\nname = \"acme/test\"; version = \"0.1.0\""
  let doc = @moon-manifest.parse(Mod, source)
  assert_eq(doc.diagnostics.length(), 0)
  let desc = doc.string_field("description").unwrap()
  assert_eq(
    @utf8.decode_lossy(doc.source[desc.span.start:desc.span.end]),
    "\"😀 中文\"",
  )
  let entry = doc.string_field("name").unwrap()
  assert_eq(
    @utf8.decode_lossy(doc.source[entry.span.start:entry.span.end]),
    "\"acme/test\"",
  )
  let same_line = @moon-manifest.parse(
    Mod,
    "description = \"😀\"; version = \"0.1.0\"",
  )
  assert_eq(same_line.diagnostics.length(), 0)
  let version = same_line.string_field("version").unwrap()
  assert_eq(
    @utf8.decode_lossy(same_line.source[version.span.start:version.span.end]),
    "\"0.1.0\"",
  )
  assert_eq(@utf8.decode_lossy(doc.source), source)
}

///|
test "legacy options private emits warning while staying readable" {
  let doc = @moon-manifest.parse(
    Mod,
    "name = \"acme/test\"\noptions(\"private\": true)\n",
  )
  assert_true(doc.is_private())
  assert_eq(doc.diagnostics.length(), 0)
  assert_true(!doc.warnings.is_empty())
}

///|
test "wrong scalar and member types cannot disappear from read models" {
  let mod_diags = ["name = 42", "version = false", "source = []"].map(source => {
    @moon-manifest.parse(Mod, source).diagnostics
  })
  debug_inspect(
    mod_diags,
    content=(
      #|[
      #|  [{ message: "Invalid value type for `name`", start: 7, end: 9 }],
      #|  [{ message: "Invalid value type for `version`", start: 10, end: 15 }],
      #|  [{ message: "Invalid value type for `source`", start: 9, end: 11 }],
      #|]
    ),
  )
  let work_diags = ["members = 42", "members = [\"a\", 42]"].map(source => {
    @moon-manifest.parse(Work, source).diagnostics
  })
  debug_inspect(
    work_diags,
    content=(
      #|[
      #|  [{ message: "Invalid value type for `members`", start: 10, end: 12 }],
      #|  [{ message: "Invalid value type for `members`", start: 10, end: 19 }],
      #|]
    ),
  )
}
