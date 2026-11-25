# unmbt/moon-manifest

Lossless readers and editors for MoonBit `moon.mod`, `moon.pkg`, and
`moon.work` files.

The package is used by MoonBit release and dependency tools that need to
inspect or update a manifest without reformatting it. Parsing is delegated to
[`moonbitlang/moon_config`](https://mooncakes.io/docs/moonbitlang/moon_config),
while edits replace only the selected byte spans and preserve comments,
whitespace, line endings, and unrelated fields.

## Install

```bash
moon add unmbt/moon-manifest
```

Then import the package in `moon.pkg`:

```moonbit
import {
  "unmbt/moon-manifest",
}
```

## Example

```moonbit
let document = @moon-manifest.parse(
  Mod,
  "name = \"example/app\"\nversion = \"0.1.0\"\n",
)
let name = document.module_name()
let updated = document.replace_string("version", "0.2.0")
```

Multi-span lossless edits:

```moonbit
let version_span = document.string_field("version").unwrap().span
let edited_bytes = document.apply_edits([
  { span: version_span, replacement: "\"0.2.0\"" },
])
```

- `Document::dependency_version` and `Document::dependencies` read module
  dependencies with source spans.
- `Document::members` and `Document::member_entries` read workspace members.
- `Document::string_field`, `Document::field_span`, and `Document::find_string`
  query top-level AST fields without matching comments or nested options.
- `Document::replace_span`, `Document::apply_edits`, and `Document::replace_string`
  perform lossless UTF-8 byte-span edits (`EditError` on invalid/overlapping spans).
- `Document::diagnostics` and `Document::warnings` expose parser and validation
  diagnostics with byte offsets into the original UTF-8 source.
- BOM and CRLF input are preserved. `is_private` checks registry visibility
  (`private = true` or legacy `options("private": true)`).

## Supported files and targets

`Kind::Mod`, `Kind::Pkg`, and `Kind::Work` correspond to the three MoonBit
manifest formats. The library package has no async or OS dependency and checks
across all MoonBit targets; the `cmd/moon-manifest` CLI uses
`moonbitlang/core/async` and targets `native`.

## License

MIT
