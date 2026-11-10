# unmbt/moon-manifest

Lossless readers and editors for MoonBit `moon.mod`, `moon.pkg`, and
`moon.work` files.

The package is used by MoonBit release and dependency tools that need to
inspect or update a manifest without reformatting it. Parsing is delegated to
[`moonbitlang/moon_config`](https://mooncakes.io/docs/moonbitlang/moon_config),
while edits replace only the selected string value and preserve comments,
whitespace, line endings, and unrelated fields.

## Install

```bash
moon add unmbt/moon-manifest
```

Then import the package from MoonBit:

```moonbit
import "unmbt/moon-manifest"
```

## Example

```moonbit
let document = @manifest.parse(
  @manifest.Kind::Mod,
  "name = \"example/app\"\nversion = \"0.1.0\"\n",
)
let name = document.module_name()
let updated = document.replace_string("version", "0.2.0")
```

`Document::dependency_version` reads a dependency from a parsed manifest;
`Document::members` reads workspace members; `Document::find_string` returns a
byte span for a scalar string; and `Document::replace_string` performs a
lossless replacement. `Document::diagnostics` exposes parser diagnostics with
byte offsets into the original UTF-8 source.

The 0.2 alpha adds AST-scoped `string_field`, `field_span`,
`member_entries`, `dependencies`, and `is_private` queries. Located values
refer to complete literals in the original UTF-8 bytes (including quotes).
Import spans cover the whole `name@version` literal. Duplicate imports and
unsupported module import aliases/kinds are diagnosed instead of omitted.
BOM and CRLF input are preserved. `is_private` describes registry visibility,
not an npm-style prohibition on publishing.

The CLI uses `moonbitlang/core/async`; the library itself has no async dependency.

## Supported files and targets

`Kind::Mod`, `Kind::Pkg`, and `Kind::Work` correspond to the three MoonBit
manifest formats. The package targets native because it is intended for CLI,
release, and workspace tooling.

## License

MIT
