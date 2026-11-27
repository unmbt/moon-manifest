///|
/// A supported MoonBit configuration file.
#derive(Eq, Debug)
pub(all) enum Kind {
  Mod
  Pkg
  Work
}

///|
fn Kind::default_path(self : Kind) -> String {
  match self {
    Mod => "moon.mod"
    Pkg => "moon.pkg"
    Work => "moon.work"
  }
}

///|
/// A diagnostic reported by `moon_config` or by the manifest validation layer.
#derive(Eq, Debug)
pub struct Diagnostic {
  message : String
  start : Int32
  end : Int32
}

///|
/// A byte range in the original UTF-8 source.
#derive(Eq, Debug)
pub(all) struct Span {
  start : Int32
  end : Int32
}

///|
/// A parsed manifest. `source` is retained byte-for-byte for lossless edits and
/// stale-plan checks.
#derive(Debug)
pub struct Document {
  kind : Kind
  path : String
  source : Bytes
  priv ast : @moon_config.Ast
  priv char_byte_offsets : Array[Int32]
  diagnostics : Array[Diagnostic]
  warnings : Array[Diagnostic]
}

///|
/// Parse a MoonBit manifest (`moon.mod`, `moon.pkg`, or `moon.work`) while
/// retaining the original UTF-8 bytes for lossless edits.
///
/// # Example
/// ```mbt check
/// test {
///   let doc = @moon-manifest.parse(
///     Mod,
///     "name = \"example/app\"\nversion = \"0.1.0\"\n",
///   )
///   debug_inspect(doc.module_name(), content="Some(\"example/app\")")
///   debug_inspect(doc.version(), content="Some(\"0.1.0\")")
/// }
/// ```
pub fn parse(kind : Kind, source : String, path? : String) -> Document {
  let resolved_path = match path {
    Some(path) => path
    None => kind.default_path()
  }
  let input = match source.strip_prefix("\uFEFF") {
    Some(rest) => " \{rest}"
    None => source
  }
  let result = match kind {
    Mod => @moon_config.parse_moon_mod(name=resolved_path, input)
    Pkg => @moon_config.parse_moon_pkg(name=resolved_path, input)
    Work => @moon_config.parse_moon_work(name=resolved_path, input)
  }
  let char_byte_offsets = build_char_byte_offsets(source)
  let diagnostics = result.diagnostics.errors.map(report => {
    report_to_diagnostic(char_byte_offsets, report)
  })
  let warnings = result.diagnostics.warnings.map(report => {
    report_to_diagnostic(char_byte_offsets, report)
  })
  let document : Document = {
    kind,
    path: resolved_path,
    source: @utf8.encode(source),
    ast: result.ast,
    char_byte_offsets,
    diagnostics,
    warnings,
  }
  document.validate()
  document
}

///|
fn build_char_byte_offsets(source : String) -> Array[Int32] {
  let offsets : Array[Int32] = [0]
  let mut byte_offset = 0
  for ch in source {
    let cp = ch.to_int()
    byte_offset += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    offsets.push(byte_offset)
  }
  offsets
}

///|
fn position_to_byte(
  char_byte_offsets : Array[Int32],
  position : @basic.Position,
) -> Int32 {
  let idx = position.cnum
  if idx <= 0 {
    0
  } else if idx >= char_byte_offsets.length() {
    char_byte_offsets[char_byte_offsets.length() - 1]
  } else {
    char_byte_offsets[idx]
  }
}

///|
fn report_to_diagnostic(
  char_byte_offsets : Array[Int32],
  report : @basic.Report,
) -> Diagnostic {
  {
    message: report.msg,
    start: position_to_byte(char_byte_offsets, report.loc.start),
    end: position_to_byte(char_byte_offsets, report.loc.end),
  }
}
