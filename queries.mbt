///|
/// A value and its complete literal span in the original UTF-8 source.
#derive(Eq, Debug)
pub struct LocatedString {
  value : String
  span : Span
}

///|
#derive(Eq, Debug)
pub struct Dependency {
  name : String
  version : String
  span : Span
}

///|
fn Document::span(self : Document, value : @moon_config.Ast) -> Span {
  let source = @utf8.decode_lossy(self.source)
  let loc = value.loc()
  {
    start: position_to_byte(source, loc.start),
    end: position_to_byte(source, loc.end),
  }
}

///|
/// Query a top-level string field, never a nested field with the same name.
pub fn Document::string_field(self : Document, key : String) -> LocatedString? {
  for (name, value) in fields(self.ast) {
    if name == key && value is @moon_config.Str(text, ..) {
      return Some({ value: text, span: self.span(value), })
    }
  }
  None
}

///|
pub fn Document::member_entries(self : Document) -> Array[LocatedString] {
  let result = []
  for (key, value) in fields(self.ast) {
    if key == "members" && value is @moon_config.Arr(items, ..) {
      for item in items {
        if item is @moon_config.Str(text, ..) {
          result.push({ value: text, span: self.span(item), })
        }
      }
    }
  }
  result
}

///|
/// A MoonBit private module requests restricted registry visibility.
pub fn Document::is_private(self : Document) -> Bool {
  for (key, value) in fields(self.ast) {
    if key == "private" && value is @moon_config.Bool(flag, ..) {
      return flag
    }
  }
  false
}

///|
pub fn Document::field_span(self : Document, key : String) -> Span? {
  for (name, value) in fields(self.ast) {
    if name == key {
      return Some(self.span(value))
    }
  }
  None
}

///|
/// Import literal spans include the name, version, and surrounding quotes.
pub fn Document::dependencies(self : Document) -> Array[Dependency] {
  let result = []
  for (key, value) in fields(self.ast) {
    if key == "deps" {
      for (name, item) in fields(value) {
        if item is @moon_config.Str(version, ..) {
          result.push({ name, version, span: self.span(item), })
        }
      }
    }
  }
  result
}

///|
fn validate_imports(
  input : String,
  source : String,
  path : String,
) -> Array[Diagnostic] {
  let (raw, _) = @moon_config.parse_moon_pkg(input, name=path)
  let diagnostics = []
  let seen : Map[String, Bool] = Map([])
  for (key, value) in fields(raw) {
    if key == "import" || key == "test-import" || key == "wbtest-import" {
      if value is @moon_config.Arr(items, ..) {
        for item in items {
          let message = match item {
            @moon_config.Str(spec, ..) if key == "import" => {
              let name = match spec.rev_find("@") {
                Some(i) if i > 0 => spec[:i].to_owned()
                _ => spec
              }
              if seen.contains(name) {
                "Duplicate dependency `\{name}`"
              } else {
                seen[name] = true
                ""
              }
            }
            _ =>
              "Unsupported module import: expected a plain module@version string"
          }
          if message != "" {
            let loc = item.loc()
            diagnostics.push({
              message,
              start: position_to_byte(source, loc.start),
              end: position_to_byte(source, loc.end),
            })
          }
        }
      }
    }
  }
  diagnostics
}
