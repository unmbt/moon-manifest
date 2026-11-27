///|
test "official moon.mod parsing and lossless version edit" {
  let source = "// 😀\r\nname = \"example/demo\"\r\nversion = \"0.1.0\"\r\n"
  let document = @moon-manifest.parse(Mod, source)
  assert_eq(document.module_name(), Some("example/demo"))
  assert_eq(document.version(), Some("0.1.0"))
  let edited = document.replace_string("version", "1.0.0-beta.1")
  assert_true(edited.contains("// 😀\r\n"))
  assert_true(edited.contains("version = \"1.0.0-beta.1\"\r\n"))
}

///|
test "official workspace members are read" {
  let document = @moon-manifest.parse(
    Work,
    "members = [\"./a\", \"../b\"]",
    path="moon.work",
  )
  assert_eq(document.members(), ["./a", "../b"])
}

///|
test "commented, string, and nested option occurrences are ignored" {
  let source = "// version = \"bad\"\nname = \"version = bad\"\noptions(\"version\": \"nested\")\nversion = \"1\"\n"
  let document = @moon-manifest.parse(Mod, source)
  assert_eq(
    document.replace_string("version", "2"),
    "// version = \"bad\"\nname = \"version = bad\"\noptions(\"version\": \"nested\")\nversion = \"2\"\n",
  )
}

///|
test "default path matches manifest kind" {
  assert_eq(@moon-manifest.parse(Mod, "").path, "moon.mod")
  assert_eq(@moon-manifest.parse(Pkg, "").path, "moon.pkg")
  assert_eq(@moon-manifest.parse(Work, "").path, "moon.work")
}
