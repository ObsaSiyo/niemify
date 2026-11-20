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
cli convert examples/exchange.xml "$work/exchange.json" --schema exchange-demo
cli convert "$work/exchange.json" "$work/roundtrip.xml" --schema exchange-demo
cli verify "$work/roundtrip.xml"
if cli convert examples/exchange.xml "$work/exchange.json" >"$work/out" 2>"$work/err"; then
  echo 'convert overwrote an existing file' >&2
  exit 1
fi
grep -q 'already exists' "$work/err"
printf '<wrong/>' >"$work/wrong.xml"
if cli convert "$work/wrong.xml" "$work/invalid.json" --schema exchange-demo >"$work/out" 2>"$work/err"; then
  echo 'convert accepted schema-invalid XML' >&2
  exit 1
fi
test ! -e "$work/invalid.json"
echo 'CLI: round trip, schema validation, and output protection passed'
