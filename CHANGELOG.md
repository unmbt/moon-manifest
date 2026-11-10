# Changelog

## 0.2.0-alpha.2

- Diagnose non-string module fields and malformed workspace member arrays instead of treating them as absent.

## 0.2.0-alpha.1

- Add AST-scoped located fields, members and dependency enumeration for workspace tooling.
- Preserve BOM and Unicode byte locations; diagnose duplicate and unsupported module imports.
- Move the CLI to core/async and validate on MoonBit 0.10.20.

This prerelease supports moonset development; stable release follows end-to-end validation.
