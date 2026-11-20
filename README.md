# niemify

**Convert and validate NIEM exchange XML.** niemify is a Lua CLI and library for ordered XML ↔ JSON conversion and validation against a supplied XSD. It does not map arbitrary data into NIEM or certify conformance.

## Install

Requires Lua 5.4, LuaRocks, and Lua 5.4 and Expat development headers (for building dependencies). On Debian/Ubuntu, install `liblua5.4-dev` and `libexpat1-dev`. XSD validation also needs `xmllint` on `PATH` (`libxml2-utils` on Debian/Ubuntu). The CLI targets macOS and Linux.

```sh
luarocks --lua-version=5.4 make niemify-2.0.0-1.rockspec
niemify help
```

This is a local build from the checkout, not a publication to the LuaRocks package registry. If you use a custom LuaRocks tree, add its `bin` directory to `PATH`.

Use `niemify help <command>` or `niemify <command> --help` for command-specific usage and examples.

## Run the development task ledger

Start a **fresh interactive OMP session** with `omp` from the repository root, then enter `/skill:build`. The [project extension](.omp/extensions/build.ts) loads at session startup and dispatches OMP’s native `/loop` with the fixed verification prompt. A session opened before the extension was added may expand the skill as text instead of starting the loop; reopen OMP from this checkout. Headless sessions do not run this command.

## Integration demo: warehouse → inventory catalog

A fictional warehouse sends two stock counts to a catalog. The [exchange schema](examples/inventory/exchange.xsd) defines the update and imports a [shared identifier schema](examples/inventory/common.xsd) from a relative path. The shared schema requires three uppercase letters, a hyphen, and four digits for each SKU.

Run from the checkout with `niemify` installed:

```sh
work=$(mktemp -d)
export NIEMIFY_HOME="$work/config"
niemify upload inventory examples/inventory/exchange.xsd
niemify convert examples/inventory/valid.xml "$work/inventory.json" --schema inventory
cat "$work/inventory.json"
niemify convert "$work/inventory.json" "$work/roundtrip.xml" --schema inventory
niemify verify "$work/roundtrip.xml" --schema inventory
```

The JSON preserves both item elements in order, the `warehouse` attribute, and the `common:Sku` prefix. Here is the first SKU node:

```json
{
  "type": "element",
  "name": "common:Sku",
  "elements": [{ "type": "text", "text": "BOX-0007" }]
}
```

The [invalid example](examples/inventory/invalid.xml) is well-formed XML, but this command exits nonzero because `box-7` violates the imported SKU pattern:

```sh
niemify verify examples/inventory/invalid.xml --schema inventory
```

Both schemas and all records are synthetic; they are not official NIEM artifacts.

## Convert and verify

Run `niemify` or `niemify --help` for quick examples and grouped commands. Use `niemify help <command>` or `niemify <command> --help` for command-specific usage. `verify` help shows the XSD-only example first, followed by the optional NIEM check; `convert` help shows both directions and data-only stdout. Help does not need local configuration or external validators.

An unknown command suggests a correction only if exactly one command name is one edit away. Otherwise, it points to `niemify --help`. Suggestions are never executed.

Invalid options and missing operands show usage. For a file error, check the path named on stderr; if the conversion destination already exists, choose another path or use `-` for stdout.

```sh
niemify convert examples/exchange.xml exchange.json --schema exchange-demo
niemify convert exchange.json exchange-roundtrip.xml --schema exchange-demo
niemify verify exchange-roundtrip.xml
```

`convert` infers direction from the input extension, uses UTF-8, and refuses to overwrite an existing output. Use `-` as output to write to stdout. Pass `--schema` to validate on conversion. `verify` defaults to the active schema. Commands exit nonzero on failure.

File conversions report the destination and format on stderr. With `-` as the output, stdout contains only the converted data.

XML becomes a JSON document tree whose `elements` arrays preserve child order. Qualified names, attributes, namespace declarations, repeated nodes, and mixed text are kept; exact XML formatting is not. XML with DTDs is rejected.

### Check an existing exchange

For a one-off XSD check, pass the entry schema path. No registration, Java, or SCHEval is needed:

```sh
niemify verify examples/inventory/valid.xml --schema examples/inventory/exchange.xsd
```

This reports XML syntax, XSD validity, and `NIEM NDR: Not checked`. Keep the imported schemas in their original relative locations.

### Opt in to NIEM 6.0 extension checks

This profile checks the entry XSD’s [NIEM 6.0 `ExtensionSchemaDocument` target](https://docs.oasis-open.org/niemopen/ndr/v6.0/os/niem-ndr-v6.0-os.html#61-conformance-targets). It requires network-denied Linux with no capabilities and no new privileges, Java 25, `sha256sum`, `timeout`, [SCHEval `scheval-1.2.zip` from CMFTool v1.2.1](https://github.com/niemopen/cmftool/releases/tag/v1.2.1) on `PATH`, and the [pinned extension rule tree](https://github.com/niemopen/niem-naming-design-rules/tree/33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817/sch). Prepare the local [NIEM Model 6.0](https://docs.oasis-open.org/niemopen/niem-model/v6.0/os/niem-model-v6.0-os.html) schemas and catalog before disabling networking. See the [fixture setup and pinned hashes](tests/fixtures/niem6-extension/README.md).

From the staged fixture directory in that environment:

```sh
niemify verify sample.xml --schema extension.xsd --niem 6.0 \
  --rules rules/sch/extTarget-6.0.sch --catalog model/xsd/xml-catalog.xml
```

Replace `extension.xsd` with `extension-rule9-94.xsd` to see a mandatory NDR failure after XSD passes. Use `--catalog` when rules need to resolve local dependencies; it does not change basic XSD resolution. If NDR is **Unable to run**, check the named prerequisite or follow the CLI hint: omit `--niem`, `--rules`, and `--catalog` to retry XSD only. If NDR **Failed**, fix the cited rule in the entry schema and rerun the same check. Warnings do not fail the check.

An automated pass is not certification or full NIEM conformance. Manual review remains required. Use [NIEMOpen CMFTool](https://github.com/niemopen/cmftool) for upstream model authoring and translation, not this verifier.

## Manage schemas

```sh
niemify setup
niemify list
niemify upload my-exchange /path/to/exchange.xsd
niemify switch my-exchange
niemify config
niemify update my-exchange /path/to/new/exchange.xsd
niemify verify /path/to/exchange.xml
```

`exchange-demo` is synthetic, not an official NIEM schema. Register only trusted local schemas. `upload` and `update` register the source path rather than copying it, so relative imports still work. Leave all referenced files in place. Validation does not fetch network resources. Set `NIEMIFY_HOME` to use a separate configuration directory.

## Library

```lua
local niemify = require('niemify')
local tree = niemify.xml('<message id="1">hello</message>')
local roundtrip = niemify.json(tree)
local from_table = niemify.json({ message = { text = 'hello' } })
assert(niemify.validate(from_table, 'xml'))
```

- `convert(input, type, options)` defaults to XML input. `xml` returns a document table; `json` accepts that table, a plain table with one root key, or JSON text and returns XML.
- `json` accepts `rootElement` to wrap a plain table and `namespace` to declare its default namespace or prefix map.
- `validate` returns `true` or raises an error. The `schema` option selects a named XSD, and `validate = true` uses the active XSD if none is named. Without either option, the API checks conversion validity only.
- `list()` and `builtin()` return available and bundled schema names, respectively.

Run `sh tests/run.sh` from the checkout after installing dependencies. Set `LUA` to the Lua 5.4 binary if needed.

MIT licensed.
