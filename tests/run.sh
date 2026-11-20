#!/bin/sh
set -eu

lua=${LUA:-lua5.4}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/state"
export NIEMIFY_HOME="$work/state"
"$lua" tests/converter.lua
"$lua" tests/schema.lua
export NIEMIFY_HOME="$work/cli-state"

cli() { "$lua" bin/niemify "$@"; }
cli help convert >"$work/help"
cli convert --help >"$work/flag-help"
cmp "$work/help" "$work/flag-help"
grep -Fq 'niemify convert exchange.xml exchange.json' "$work/help"
if cli verify >"$work/out" 2>"$work/err"; then
  echo 'verify accepted a missing input operand' >&2
  exit 1
fi
test ! -s "$work/out"
grep -Fq 'Usage: niemify verify <input.xml>' "$work/err"
cli convert examples/exchange.xml "$work/exchange.json" --schema exchange-demo >"$work/out" 2>"$work/err"
test ! -s "$work/out"
grep -Fq "Wrote $work/exchange.json (XML to JSON)." "$work/err"
cli convert examples/exchange.xml - --schema exchange-demo >"$work/stdout.json" 2>"$work/err"
test ! -s "$work/err"
"$lua" - "$work/stdout.json" <<'LUA'
local stream <close> = assert(io.open(arg[1], 'r'))
local data, _, err = require('dkjson').decode(stream:read('a'))
assert(data and not err and data.elements[1].name == 'ex:Exchange')
LUA
cli convert "$work/exchange.json" "$work/roundtrip.xml" --schema exchange-demo
cli verify "$work/roundtrip.xml"
if cli convert examples/exchange.xml "$work/exchange.json" >"$work/out" 2>"$work/err"; then
  echo 'convert overwrote an existing file' >&2
  exit 1
fi
grep -q 'already exists' "$work/err"
grep -Fq 'choose another output path, or use - for stdout' "$work/err"
printf '<wrong/>' >"$work/wrong.xml"
if cli convert "$work/wrong.xml" "$work/invalid.json" --schema exchange-demo >"$work/out" 2>"$work/err"; then
  echo 'convert accepted schema-invalid XML' >&2
  exit 1
fi
test ! -e "$work/invalid.json"
echo 'CLI: round trip, schema validation, and output protection passed'

demo=examples/inventory
cli upload inventory "$demo/exchange.xsd" >"$work/out"
cli convert "$demo/valid.xml" "$work/inventory.json" --schema inventory
"$lua" - "$work/inventory.json" <<'LUA'
local file <close> = assert(io.open(arg[1], 'r'))
local document = assert(require('dkjson').decode(file:read('a')))
local root = document.elements[1]
assert(root.name == 'inv:InventoryUpdate' and root.attributes.warehouse == 'DEMO-WH-01')
local skus = {}
for _, item in ipairs(root.elements) do
  if item.name == 'inv:Item' then
    for _, child in ipairs(item.elements) do
      if child.name == 'common:Sku' then skus[#skus + 1] = child.elements[1].text end
    end
  end
end
assert(#skus == 2 and skus[1] == 'BOX-0007' and skus[2] == 'TAP-0012', 'expected both SKUs in source order')
LUA
cli convert "$work/inventory.json" "$work/inventory.xml" --schema inventory
cli verify "$work/inventory.xml" --schema inventory
if cli verify "$demo/invalid.xml" --schema inventory >"$work/out" 2>"$work/err"; then
  echo 'verify accepted a SKU that violates the imported schema' >&2
  exit 1
fi
grep -q 'box-7' "$work/err"
echo 'Integration demo: imported XSD, ordered JSON, and invalid SKU rejection passed'
