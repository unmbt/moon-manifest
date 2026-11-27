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
  version_span : Span
}

///|
fn Document::loc_to_span(self : Document, loc : @basic.Location) -> Span {
  {
    start: position_to_byte(self.char_byte_offsets, loc.start),
    end: position_to_byte(self.char_byte_offsets, loc.end),
  }
}

///|
fn Document::span(self : Document, value : @moon_config.Expr) -> Span {
  self.loc_to_span(value.loc())
}

///|
fn Document::assign_field(self : Document, key : String) -> @moon_config.Field? {
  for statement in self.ast.0 {
    if statement is Assign(field) && field.key == key {
      return Some(field)
    }
  }
  None
}

///|
fn parse_dep_spec(spec : String) -> (String, String)? {
  match spec.rev_find("@") {
    Some(i) if i > 0 => {
      let name = spec.exact_view(end=i).to_owned()
      let version = spec.exact_view(start=i + 1).to_owned()
      if version.is_empty() {
        None
      } else {
        Some((name, version))
      }
    }
    _ => None
  }
}

///|
/// Query a top-level string field, never a nested field with the same name.
pub fn Document::string_field(self : Document, key : String) -> LocatedString? {
  match self.assign_field(key) {
    Some({ value: String(str~, loc~), .. }) =>
      Some({ value: str, span: self.loc_to_span(loc), })
    _ => None
  }
}

///|
pub fn Document::field_span(self : Document, key : String) -> Span? {
  self.assign_field(key).map(field => self.span(field.value))
}

///|
/// Find a top-level string field span without matching comments or nested options.
pub fn Document::find_string(self : Document, key : String) -> Span? {
  self.string_field(key).map(entry => entry.span)
}

///|
pub fn Document::module_name(self : Document) -> String? {
  self.string_field("name").map(entry => entry.value)
}

///|
pub fn Document::version(self : Document) -> String? {
  self.string_field("version").map(entry => entry.value)
}

///|
pub fn Document::member_entries(self : Document) -> Array[LocatedString] {
  let result = []
  if self.assign_field("members") is Some({ value: Array(items~, ..), .. }) {
    for item in items {
      if item is String(str~, loc~) {
        result.push({ value: str, span: self.loc_to_span(loc), })
      }
    }
  }
  result
}

///|
pub fn Document::members(self : Document) -> Array[String] {
  self.member_entries().map(entry => entry.value)
}

///|
/// A MoonBit private module requests restricted registry visibility.
pub fn Document::is_private(self : Document) -> Bool {
  match self.assign_field("private") {
    Some({ value: Bool(value~, ..), .. }) => value
    _ =>
      match @moon_config.find_field_in_options(self.ast, "private") {
        Some(Bool(value~, ..)) => value
        _ => false
      }
  }
}

///|
fn find_unescaped_at(source : Bytes, start : Int32, end : Int32) -> Int32? {
  let mut result : Int32? = None
  let mut index = start
  let mut escaped = false
  while index < end {
    if escaped {
      escaped = false
    } else if source[index] == b'\\' {
      escaped = true
    } else if source[index] == b'@' {
      result = Some(index)
    }
    index += 1
  }
  result
}

///|
fn Document::dependency_version_span(
  self : Document,
  literal_span : Span,
) -> Span {
  if literal_span.start + 2 <= literal_span.end &&
    literal_span.end <= self.source.length() &&
    self.source[literal_span.start] == b'"' &&
    self.source[literal_span.end - 1] == b'"' {
    match
      find_unescaped_at(
        self.source,
        literal_span.start + 1,
        literal_span.end - 1,
      ) {
      Some(at) => { start: at + 1, end: literal_span.end - 1, }
      None => literal_span
    }
  } else {
    literal_span
  }
}

///|
/// Import literal spans include the name, version, and surrounding quotes;
/// `version_span` locates the version substring after `@` inside the literal.
pub fn Document::dependencies(self : Document) -> Array[Dependency] {
  let result = []
  for statement in self.ast.0 {
    if statement is Import(items~, kind=Normal, conditions=[], ..) {
      for item in items {
        if item.alias_ is None &&
          parse_dep_spec(item.path) is Some((name, version)) {
          let span = self.loc_to_span(item.path_loc)
          let version_span = self.dependency_version_span(span)
          result.push({ name, version, span, version_span, })
        }
      }
    }
  }
  result
}

///|
/// Find a declared module dependency by name.
pub fn Document::dependency(self : Document, name : String) -> Dependency? {
  for dep in self.dependencies() {
    if dep.name == name {
      return Some(dep)
    }
  }
  None
}

///|
pub fn Document::dependency_version(
  self : Document,
  dependency : String,
) -> String? {
  self.dependency(dependency).map(dep => dep.version)
}

///|
fn Document::validate(self : Document) -> Unit {
  let seen_deps : Set[String] = Set([])
  for statement in self.ast.0 {
    match statement {
      Assign(field) => {
        let valid = match (self.kind, field.key) {
          (Mod, "name" | "version" | "source") => field.value is String(_, ..)
          (Work, "members") =>
            match field.value {
              Array(items~, ..) => items.all(item => item is String(_, ..))
              _ => false
            }
          _ => true
        }
        if !valid {
          let span = self.span(field.value)
          self.diagnostics.push({
            message: "Invalid value type for `\{field.key}`",
            start: span.start,
            end: span.end,
          })
        }
      }
      Import(items~, kind=Normal, ..) if self.kind is Mod =>
        for item in items {
          if item.alias_ is Some(_) {
            let span = self.loc_to_span(item.loc)
            self.diagnostics.push({
              message: "Unsupported module import: expected a plain module@version string",
              start: span.start,
              end: span.end,
            })
          } else {
            match parse_dep_spec(item.path) {
              None => {
                let span = self.loc_to_span(item.path_loc)
                self.diagnostics.push({
                  message: "Invalid module import `\{item.path}`: expected a plain module@version string",
                  start: span.start,
                  end: span.end,
                })
              }
              Some((name, _)) =>
                if !seen_deps.insert_and_check(name) {
                  let span = self.loc_to_span(item.path_loc)
                  self.diagnostics.push({
                    message: "Duplicate dependency `\{name}`",
                    start: span.start,
                    end: span.end,
                  })
                }
            }
          }
        }
      _ => ()
    }
  }
}
