# Changelog

## Unreleased

- `verify --schema` accepts a local XSD path without registration; saved schema names still work.
- Basic `verify` reports XML syntax, the XSD result and resolved path, and that NIEM NDR was not checked.
- Failed `verify` checks distinguish malformed XML from XSD rejection and show the original sample path and line when available.
- `verify` reports a missing or invalid required XSD dependency as unable to validate, with the entry schema path and the dependency diagnostic.
- `verify --niem 6.0 --rules <file>` opts into pinned `ExtensionSchemaDocument` checks on network-denied Linux with SCHEval and Java 25. The complete SVRL report determines the rule verdict; warnings do not fail the check, and manual review remains required. See the [setup and examples](README.md#opt-in-to-niem-60-extension-checks).
- Added grouped CLI help, per-command examples, conversion receipts, and recovery hints without mixing messages into piped data.
- Added a synthetic warehouse-to-catalog exchange demonstrating relative XSD imports, ordered JSON conversion, and rejection of an invalid SKU.

## 2.0.0

- Rewrote the CLI and library in Lua 5.4 and added a LuaRocks build.
- Preserved ordered XML/JSON conversion, named schema registration, and local XSD validation.
- Started a clean public history containing only the Lua release and synthetic examples.
