# Changelog

## 0.2.0

- Migrate AST parsing and validation to `moonbitlang/moon_config@0.4.6` and `moonc v0.10.22` without double-parsing `moon.mod`.
- Fix same-line non-BMP (emoji) and BOM byte-offset calculation via single-pass UTF-8 offset indexing.
- Scope `find_string` and `replace_string` to top-level AST fields and unify query helpers.
- Add lossless byte-span editing APIs (`Document::apply_edits`, `Document::replace_span`, `TextEdit`, `EditError`) and make `Span` `pub(all)`.
- Expose `Document.warnings`, support legacy `options("private": true)` in `is_private()`, and add CLI/CI updates.

## 0.2.0-alpha.2

- Diagnose non-string module fields and malformed workspace member arrays instead of treating them as absent.

## 0.2.0-alpha.1

- Add AST-scoped located fields, members and dependency enumeration for workspace tooling.
- Preserve BOM and Unicode byte locations; diagnose duplicate and unsupported module imports.
- Move the CLI to core/async and validate on MoonBit 0.10.20.
