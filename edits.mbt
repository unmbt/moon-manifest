///|
/// Errors raised when applying lossless byte edits to a `Document`.
#derive(Eq, Debug)
pub(all) suberror EditError {
  OutOfBounds(span~ : Span, source_len~ : Int32)
  OverlappingSpans(first~ : Span, second~ : Span)
}

///|
/// A lossless replacement for a UTF-8 byte span in a `Document`.
#derive(Eq, Debug)
pub(all) struct TextEdit {
  span : Span
  replacement : String
}

///|
/// Apply a batch of non-overlapping byte-span replacements while preserving
/// comments, whitespace, line endings, and BOM byte-for-byte.
///
/// # Example
/// ```mbt check
/// test {
///   let doc = @moon-manifest.parse(
///     Mod,
///     "name = \"example/app\"\nversion = \"0.1.0\"\n",
///   )
///   let span = doc.string_field("version").unwrap().span
///   let updated = doc.apply_edits([{ span, replacement: "\"0.2.0\"", }])
///   inspect(
///     @utf8.decode_lossy(updated),
///     content=(
///       #|name = "example/app"
///       #|version = "0.2.0"
///       #|
///     ),
///   )
/// }
/// ```
pub fn Document::apply_edits(
  self : Document,
  edits : ArrayView[TextEdit],
) -> Bytes raise EditError {
  if edits.is_empty() {
    return self.source
  }
  let source_len = self.source.length()
  let sorted : Array[TextEdit] = []
  for edit in edits {
    let span = edit.span
    if span.start < 0 || span.end < span.start || span.end > source_len {
      raise OutOfBounds(span~, source_len~)
    }
    sorted.push(edit)
  }
  sorted.sort_by((a, b) => {
    if a.span.start != b.span.start {
      a.span.start - b.span.start
    } else {
      a.span.end - b.span.end
    }
  })
  for i in 1..<sorted.length() {
    let prev = sorted[i - 1].span
    let curr = sorted[i].span
    if prev.end > curr.start {
      raise OverlappingSpans(first=prev, second=curr)
    }
  }
  let buf = Buffer(capacity=source_len)
  let mut cursor = 0
  for edit in sorted {
    buf
    ..write_bytes(self.source.exact_view(start=cursor, end=edit.span.start))
    .write_string_utf8(edit.replacement)
    cursor = edit.span.end
  }
  buf.write_bytes(self.source.exact_view(start=cursor))
  buf.to_bytes()
}

///|
/// Replace a single UTF-8 byte span while preserving surrounding bytes verbatim.
pub fn Document::replace_span(
  self : Document,
  span : Span,
  replacement : String,
) -> Bytes raise EditError {
  self.apply_edits([{ span, replacement, }])
}

///|
/// Replace a top-level `key = "..."` string value while preserving comments and formatting.
///
/// # Example
/// ```mbt check
/// test {
///   let doc = @moon-manifest.parse(
///     Mod,
///     "name = \"example/app\"\nversion = \"0.1.0\"\n",
///   )
///   inspect(
///     doc.replace_string("version", "0.2.0"),
///     content=(
///       #|name = "example/app"
///       #|version = "0.2.0"
///       #|
///     ),
///   )
/// }
/// ```
pub fn Document::replace_string(
  self : Document,
  key : String,
  value : String,
) -> String {
  match self.string_field(key) {
    None => @utf8.decode_lossy(self.source)
    Some(entry) =>
      @utf8.decode_lossy(
        try! self.replace_span(entry.span, Json::string(value).stringify()),
      )
  }
}
