# niemify

A Lua CLI and library for ordered XML ↔ JSON conversion and local XSD validation. Use it with NIEM exchange documents by supplying the exchange schema and its dependencies. It does not infer NIEM mappings or certify conformance.

## Install

Requires Lua 5.4, LuaRocks, and Expat development headers (for LuaExpat). XSD validation also needs `xmllint` on `PATH` (`libxml2-utils` on Debian/Ubuntu). The CLI targets macOS and Linux.

```sh
luarocks --lua-version=5.4 make niemify-2.0.0-1.rockspec
niemify help
```

This is a local build from the checkout, not a publication to the LuaRocks package registry. If you use a custom LuaRocks tree, add its `bin` directory to `PATH`.

## Convert and verify

```sh
niemify convert examples/exchange.xml exchange.json --schema exchange-demo
niemify convert exchange.json exchange-roundtrip.xml --schema exchange-demo
niemify verify exchange-roundtrip.xml
```

`convert` infers direction from the input extension, uses UTF-8, and refuses to overwrite an existing output. Use `-` as output to write to stdout. Pass `--schema` to validate on conversion. `verify` defaults to the active schema. Commands exit nonzero on failure.

XML becomes a JSON document tree whose `elements` arrays preserve child order. Qualified names, attributes, namespace declarations, repeated nodes, and mixed text are kept; exact XML formatting is not. XML with DTDs is rejected.

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
