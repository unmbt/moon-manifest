///|
/// A supported MoonBit configuration file.
#derive(Eq, Debug)
pub(all) enum Kind {
  Mod
  Pkg
  Work
}

///|
/// A diagnostic reported by moon_config or by the lossless edit layer.
#derive(Eq, Debug)
pub struct Diagnostic {
  message : String
  start : Int32
  end : Int32
}

///|
/// A byte range in the original UTF-8 source.
#derive(Eq, Debug)
pub struct Span {
  start : Int32
  end : Int32
}

///|
/// A parsed manifest. source is retained byte-for-byte for stale-plan checks.
#derive(Debug)
pub struct Document {
  kind : Kind
  path : String
  source : Bytes
  priv ast : @moon_config.Ast
  diagnostics : Array[Diagnostic]
}

///|
pub fn parse(
  kind : Kind,
  source : String,
  path~ : String = "moon.mod",
) -> Document {
  let input = if source.has_prefix("\uFEFF") {
    " " + source[1:].to_owned()
  } else {
    source
  }
  let (ast, reports) = match kind {
    Mod => @moon_config.parse_moon_mod(name=path, input)
    Pkg => @moon_config.parse_moon_pkg(name=path, input)
    Work => @moon_config.parse_moon_work(name=path, input)
  }
  let diagnostics : Array[Diagnostic] = []
  for report in reports {
    diagnostics.push({
      message: report.msg,
      start: position_to_byte(source, report.loc.start),
      end: position_to_byte(source, report.loc.end),
    })
  }
  if kind == Mod {
    diagnostics.append(validate_imports(input, source, path))
  }
  let document = { kind, path, source: @utf8.encode(source), ast, diagnostics, }
  document.validate_shapes()
  document
}

///|
fn position_to_byte(source : String, position : @basic.Position) -> Int32 {
  let bytes = @utf8.encode(source)
  let mut line = 1
  let mut offset = 0
  while offset < bytes.length() && line < position.lnum {
    if bytes[offset] == b'\n' {
      line += 1
    }
    offset += 1
  }
  let mut line_text = ""
  let mut current_line = 1
  for item in source.split("\n") {
    if current_line == position.lnum {
      line_text = item.to_owned()
      break
    }
    current_line += 1
  }
  let local_column = position.cnum - position.bol
  let prefix = if local_column <= 0 {
    ""
  } else {
    line_text[:local_column].to_owned()
  }
  offset + @utf8.encode(prefix).length()
}

///|
fn fields(ast : @moon_config.Ast) -> Array[(String, @moon_config.Ast)] {
  match ast {
    @moon_config.Ast::Obj(items, ..) => items.to_array()
    _ => []
  }
}

///|
fn string_value(ast : @moon_config.Ast) -> String? {
  match ast {
    @moon_config.Ast::Str(value, ..) => Some(value)
    _ => None
  }
}

///|
pub fn Document::module_name(self : Document) -> String? {
  for (key, value) in fields(self.ast) {
    if key == "name" {
      return string_value(value)
    }
  }
  None
}

///|
pub fn Document::version(self : Document) -> String? {
  for (key, value) in fields(self.ast) {
    if key == "version" {
      return string_value(value)
    }
  }
  None
}

///|
pub fn Document::members(self : Document) -> Array[String] {
  for (key, value) in fields(self.ast) {
    if key == "members" {
      match value {
        @moon_config.Ast::Arr(items, ..) => {
          let result : Array[String] = []
          for item in items {
            if string_value(item) is Some(value) {
              result.push(value)
            }
          }
          return result
        }
        _ => return []
      }
    }
  }
  []
}

///|
pub fn Document::dependency_version(
  self : Document,
  dependency : String,
) -> String? {
  for (key, value) in fields(self.ast) {
    if key == "deps" {
      for (dep, version) in fields(value) {
        if dep == dependency {
          return string_value(version)
        }
      }
    }
  }
  None
}

///|
/// Find a scalar string assignment without changing comments or surrounding bytes.
pub fn Document::find_string(self : Document, key : String) -> Span? {
  find_string_span(self.source, key)
}

///|
/// Replace the first key = "..." or "key": "..." value.
pub fn Document::replace_string(
  self : Document,
  key : String,
  value : String,
) -> String {
  match find_string_span(self.source, key) {
    None => @utf8.decode_lossy(self.source)
    Some(span) => {
      let encoded = @utf8.encode(Json::string(value).stringify())
      let output = StringBuilder()
      output.write_string(@utf8.decode_lossy(self.source[:span.start]))
      output.write_string(@utf8.decode_lossy(encoded))
      output.write_string(@utf8.decode_lossy(self.source[span.end:]))
      output.to_string()
    }
  }
}

///|
fn find_string_span(source : Bytes, key : String) -> Span? {
  let key_bytes = @utf8.encode(key)
  let mut index = 0
  let mut in_string = false
  let mut escaped = false
  let mut line_comment = false
  let mut block_comment = false
  while index < source.length() {
    let current = source[index]
    let next = if index + 1 < source.length() {
      source[index + 1]
    } else {
      b'\x00'
    }
    if line_comment {
      if current == b'\n' {
        line_comment = false
      }
      index += 1
      continue
    }
    if block_comment {
      if current == b'*' && next == b'/' {
        block_comment = false
        index += 2
      } else {
        index += 1
      }
      continue
    }
    if in_string {
      if escaped {
        escaped = false
      } else if current == b'\\' {
        escaped = true
      } else if current == b'"' {
        in_string = false
      }
      index += 1
      continue
    }
    if current == b'/' && next == b'/' {
      line_comment = true
      index += 2
      continue
    }
    if current == b'/' && next == b'*' {
      block_comment = true
      index += 2
      continue
    }
    if current == b'"' {
      in_string = true
      index += 1
      continue
    }
    if index + key_bytes.length() <= source.length() &&
      source[index:index + key_bytes.length()] == key_bytes {
      let before_ok = index == 0 || !identifier_byte(source[index - 1])
      let after = index + key_bytes.length()
      let after_ok = after == source.length() || !identifier_byte(source[after])
      if before_ok && after_ok {
        let mut cursor = after
        while cursor < source.length() && whitespace(source[cursor]) {
          cursor += 1
        }
        if cursor < source.length() &&
          (source[cursor] == b'=' || source[cursor] == b':') {
          cursor += 1
          while cursor < source.length() && whitespace(source[cursor]) {
            cursor += 1
          }
          if cursor < source.length() && source[cursor] == b'"' {
            let start = cursor
            cursor += 1
            let mut escaped_value = false
            while cursor < source.length() {
              if escaped_value {
                escaped_value = false
              } else if source[cursor] == b'\\' {
                escaped_value = true
              } else if source[cursor] == b'"' {
                return Some({ start, end: cursor + 1, })
              }
              cursor += 1
            }
          }
        }
      }
    }
    index += 1
  }
  None
}

///|
fn whitespace(value : Byte) -> Bool {
  value == b' ' || value == b'\t' || value == b'\r' || value == b'\n'
}

///|
fn identifier_byte(value : Byte) -> Bool {
  (value >= b'a' && value <= b'z') ||
  (value >= b'A' && value <= b'Z') ||
  (value >= b'0' && value <= b'9') ||
  value == b'_' ||
  value == b'-'
}
