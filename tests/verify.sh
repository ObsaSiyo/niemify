#!/bin/sh
set -eu

lua=${LUA:-lua5.4}
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export LUA_PATH="$root/?.lua;$root/?/init.lua;${LUA_PATH:-;}"

cli() { "$lua" "$root/bin/niemify" "$@"; }

case ${1:-} in
  direct-path|basic-result|invalid-message|missing-import|ndr-dispatch) ;;
  *) echo 'Usage: sh tests/verify.sh direct-path|basic-result|invalid-message|missing-import|ndr-dispatch' >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$root/examples/inventory/"*.xsd "$work/"
cp "$root/examples/inventory/valid.xml" "$work/"
cd "$work"
export NIEMIFY_HOME="$work/unused-state"

if [ "$1" = ndr-dispatch ]; then
  fixture=${NDR_QUALIFIED_DIR:?set NDR_QUALIFIED_DIR to the staged SCHEval fixture}
  sample="$root/tests/fixtures/niem6-extension/sample.xml"
  rules="$fixture/rules/sch/extTarget-6.0.sch"
  catalog="$fixture/model/xsd/xml-catalog.xml"
  entry="$fixture/extension.xsd"

  cli verify "$sample" --schema "$entry" --niem 6.0 --rules "$rules" --catalog "$catalog" >out 2>err
  grep -Fxq "XSD validation: Passed ($entry)" out
  grep -Fxq 'NIEM NDR: Passed' out
  grep -Fxq 'Manual review still required' out
  grep -Fq '33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817' out
  test ! -s err

  if cli verify "$sample" --schema "$fixture/extension-rule9-94.xsd" \
      --niem 6.0 --rules "$rules" --catalog "$catalog" >out 2>err; then
    echo 'verify passed a mandatory rule violation' >&2
    exit 1
  fi
  test ! -s out
  grep -Fq 'XSD validation: Passed' err
  grep -Fxq 'NIEM NDR: Failed' err
  grep -Fq 'error: Rule 9-94:' err
  grep -Fxq 'Manual review still required' err

  if cli verify "$sample" --schema "$entry" --niem 6.0 --rules "$work/missing.sch" >out 2>err; then
    echo 'verify passed without the requested rules' >&2
    exit 1
  fi
  test ! -s out
  grep -Fxq 'NIEM NDR: Unable to run' err
  grep -Fxq 'Pinned NIEM rules file is missing' err
  if cli verify "$sample" --schema "$entry" --catalog "$catalog" >out 2>err; then
    echo 'verify accepted a catalog without a NIEM profile' >&2
    exit 1
  fi
  grep -Fq -- '--rules and --catalog require --niem 6.0' err

  PATH=/usr/bin:/bin cli verify "$sample" --schema "$entry" >out 2>err
  grep -Fxq 'NIEM NDR: Not checked' out
  test ! -s err
  test ! -e "$NIEMIFY_HOME"
  echo 'NIEM opt-in: clean, mandatory failure, unavailable, and basic retry verified.'
  exit 0
fi

if [ "$1" = basic-result ]; then
  cli verify valid.xml --schema exchange.xsd >direct.out 2>direct.err
  test ! -e "$NIEMIFY_HOME"
  export NIEMIFY_HOME="$work/registered-state"
  cli upload inventory exchange.xsd >/dev/null
  cli verify valid.xml --schema inventory >named.out 2>named.err
  printf '%s\n' 'XML syntax: Well-formed' \
    "XSD validation: Passed ($(pwd -P)/exchange.xsd)" \
    'NIEM NDR: Not checked' >expected.out
  diff -u expected.out direct.out
  diff -u expected.out named.out
  test ! -s direct.err
  test ! -s named.err
  cat direct.out
  printf '%s\n' 'Direct-path and named-schema success reports verified.'
  exit 0
fi

if [ "$1" = invalid-message ]; then
  printf '<root>\n</wrong>\n' >malformed.xml
  cp "$root/examples/inventory/invalid.xml" 'bad%sku.xml'
  if cli verify malformed.xml --schema ./missing.xsd >out 2>err; then
    echo 'verify accepted malformed XML' >&2
    exit 1
  fi
  test ! -s out
  grep -Fxq 'XML syntax: Failed' err
  grep -Fxq 'XSD validation: Skipped' err
  grep -Fxq 'NIEM NDR: Not checked' err
  grep -Fq 'malformed.xml: Malformed XML: line 2' err
  if cli verify 'bad%sku.xml' --schema ./exchange.xsd >out 2>err; then
    echo 'verify accepted the invalid SKU' >&2
    exit 1
  fi
  test ! -s out
  grep -Fxq 'XML syntax: Well-formed' err
  grep -Fxq 'XSD validation: Failed' err
  grep -Fxq 'NIEM NDR: Not checked' err
  grep -Eq '^bad%sku\.xml:[0-9]+:.*box-7' err
  test ! -e "$NIEMIFY_HOME"
  printf '%s\n' 'Malformed XML and XSD rejection reported separately on stderr.'
  exit 0
fi

if [ "$1" = missing-import ]; then
  entry="$(pwd -P)/exchange.xsd"
  mv common.xsd common.saved
  assert_unavailable() {
    if cli verify valid.xml --schema "$entry" >out 2>err; then
      echo 'verify accepted an unavailable schema dependency' >&2
      exit 1
    fi
    test ! -s out
    grep -Fxq 'XML syntax: Well-formed' err
    grep -Fxq "XSD validation: Unable to validate ($entry)" err
    grep -Fxq 'NIEM NDR: Not checked' err
    grep -Fq 'common.xsd' err
    test ! -e "$NIEMIFY_HOME"
    cmp exchange.xsd "$root/examples/inventory/exchange.xsd"
    cmp valid.xml "$root/examples/inventory/valid.xml"
  }
  assert_unavailable
  test ! -e common.xsd
  printf '<broken' >common.xsd
  assert_unavailable
  test "$(cat common.xsd)" = '<broken'
  mv common.saved common.xsd
  cli verify valid.xml --schema "$entry" >out 2>err
  grep -Fxq "XSD validation: Passed ($entry)" out
  test ! -s err
  test ! -e "$NIEMIFY_HOME"
  cmp common.xsd "$root/examples/inventory/common.xsd"
  cmp exchange.xsd "$root/examples/inventory/exchange.xsd"
  cmp valid.xml "$root/examples/inventory/valid.xml"
  printf '%s\n' 'Missing and malformed XSD imports prevented validation; restoring the import passed without writing config or fixtures.'
  exit 0
fi

cli verify valid.xml --schema ./exchange.xsd
cli verify valid.xml --schema exchange.xsd
cli verify valid.xml --schema "$work/exchange.xsd"
if cli verify valid.xml --schema ./missing.xsd >out 2>err; then
  echo 'verify accepted a missing schema file' >&2
  exit 1
fi
grep -Fq 'Schema file not found: ./missing.xsd' err
if cli convert valid.xml - --schema ./exchange.xsd >out 2>err; then
  echo 'convert unexpectedly accepted an unregistered schema path' >&2
  exit 1
fi
test ! -e "$NIEMIFY_HOME"

export NIEMIFY_HOME="$work/registered-state"
cli upload inventory ./exchange.xsd >/dev/null
cli verify valid.xml --schema inventory
cli switch inventory >/dev/null
cli verify valid.xml

printf '%s\n' 'Direct paths, local imports, and registered/active schemas verified.'
