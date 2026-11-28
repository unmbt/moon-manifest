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
fn hex_digit(ch : Char) -> Int32? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
fn unescape_string_literal(raw : String) -> String {
  if !raw.contains("\\") {
    return raw
  }
  let chars = raw.to_array()
  let len = chars.length()
  let buf = StringBuilder()
  let mut i = 0
  while i < len {
    let ch = chars[i]
    if ch == '\\' && i + 1 < len {
      let next = chars[i + 1]
      match next {
        '\\' => {
          buf.write_char('\\')
          i += 2
        }
        '"' => {
          buf.write_char('"')
          i += 2
        }
        '\'' => {
          buf.write_char('\'')
          i += 2
        }
        'n' => {
          buf.write_char('\n')
          i += 2
        }
        'r' => {
          buf.write_char('\r')
          i += 2
        }
        't' => {
          buf.write_char('\t')
          i += 2
        }
        'b' => {
          buf.write_char('\b')
          i += 2
        }
        'f' => {
          buf.write_char('\u{000C}')
          i += 2
        }
        '0' => {
          buf.write_char('\u{0000}')
          i += 2
        }
        'u' =>
          if i + 2 < len && chars[i + 2] == '{' {
            let mut j = i + 3
            let mut code = 0
            let mut count = 0
            let mut valid = true
            while j < len && chars[j] != '}' {
              match hex_digit(chars[j]) {
                Some(d) => {
                  code = code * 16 + d
                  count += 1
                }
                None => valid = false
              }
              j += 1
            }
            if valid && count > 0 && j < len && chars[j] == '}' {
              match Int32::to_char(code) {
                Some(decoded) => {
                  buf.write_char(decoded)
                  i = j + 1
                }
                None => {
                  buf.write_char(ch)
                  i += 1
                }
              }
            } else {
              buf.write_char(ch)
              i += 1
            }
          } else if i + 5 < len {
            match
              (
                hex_digit(chars[i + 2]),
                hex_digit(chars[i + 3]),
                hex_digit(chars[i + 4]),
                hex_digit(chars[i + 5]),
              ) {
              (Some(a), Some(b), Some(c), Some(d)) => {
                let code = ((a * 16 + b) * 16 + c) * 16 + d
                match Int32::to_char(code) {
                  Some(decoded) => {
                    buf.write_char(decoded)
                    i += 6
                  }
                  None => {
                    buf.write_char(ch)
                    i += 1
                  }
                }
              }
              _ => {
                buf.write_char(ch)
                i += 1
              }
            }
          } else {
            buf.write_char(ch)
            i += 1
          }
        _ => {
          buf.write_char(ch)
          buf.write_char(next)
          i += 2
        }
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

///|
/// Query a top-level string field, never a nested field with the same name.
pub fn Document::string_field(self : Document, key : String) -> LocatedString? {
  match self.assign_field(key) {
    Some({ value: String(str~, loc~), .. }) =>
      Some({ value: unescape_string_literal(str), span: self.loc_to_span(loc), })
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
        result.push({
          value: unescape_string_literal(str),
          span: self.loc_to_span(loc),
        })
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
/// Query script entries declared in `options(scripts: { ... })` with their value spans.
pub fn Document::script_entries(
  self : Document,
) -> Array[(String, LocatedString)] {
  let result = []
  if @moon_config.find_field_in_options(self.ast, "scripts")
    is Some(Map(fields~, ..)) {
    for field in fields {
      if field.value is String(str~, loc~) {
        result.push(
          (
            unescape_string_literal(field.key),
            {
              value: unescape_string_literal(str),
              span: self.loc_to_span(loc),
            },
          ),
        )
      }
    }
  }
  result
}

///|
/// Query scripts declared in `options(scripts: { ... })`.
pub fn Document::scripts(self : Document) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in self.script_entries() {
    let (name, script) = entry
    result[name] = script.value
  }
  result
}

///|
/// Query a single named script from `options(scripts: { ... })`.
pub fn Document::script(self : Document, name : String) -> String? {
  self.scripts().get(name)
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
          } else if item.path.has_prefix("./") || item.path.has_prefix("../") {
            ()
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
  if self.kind is Mod {
    match @moon_config.find_field_in_options(self.ast, "scripts") {
      Some(Map(fields~, ..)) =>
        for field in fields {
          if !(field.value is String(_, ..)) {
            let span = self.span(field.value)
            self.diagnostics.push({
              message: "Invalid value type for script `\{field.key}`",
              start: span.start,
              end: span.end,
            })
          }
        }
      Some(other) => {
        let span = self.span(other)
        self.diagnostics.push({
          message: "Invalid value type for `scripts`",
          start: span.start,
          end: span.end,
        })
      }
      None => ()
    }
  }
}
