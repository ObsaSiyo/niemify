#!/bin/sh
set -eu

case ${1:-} in
  root-help|command-help|command-typo|recover|ndr-retry) ;;
  *) echo 'Usage: sh tests/cli-usability.sh root-help|command-help|command-typo|recover|ndr-retry' >&2; exit 2 ;;
esac

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
lua=$(command -v "${LUA:-lua5.4}")
case $lua in /*) ;; *) lua=$PWD/$lua ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/cwd"
test_case=$1
case $test_case in
  recover|ndr-retry)
    xmllint=$(command -v xmllint)
    ln -s "$xmllint" "$work/bin/xmllint"
    ;;
esac

cli() (
  cd "$work/cwd"
  export PATH="$work/bin" NIEMIFY_HOME="$work/state"
  export LUA_PATH_5_4="$root/?.lua;$root/?/init.lua;${LUA_PATH_5_4:-${LUA_PATH:-;}}"
  case $test_case in
    recover|ndr-retry) ;;
    *) export LUA_INIT_5_4='local function reject() io.stderr:write("unexpected external command\n"); os.exit(1) end; os.execute, io.popen = reject, reject' ;;
  esac
  "$lua" "$root/bin/niemify" "$@"
)

check_clean() {
  test ! -e "$work/state"
  test -z "$(ls -A "$work/cwd")"
}

reject() {
  if cli "$@" >"$work/out" 2>"$work/err"; then
    echo "Expected failure: niemify $*" >&2
    exit 1
  fi
  test ! -s "$work/out"
}

if [ "$test_case" = ndr-retry ]; then
  fixture=${NDR_QUALIFIED_DIR:?set NDR_QUALIFIED_DIR to the staged NIEM fixture directory}
  case $fixture in /*) ;; *) echo 'NDR_QUALIFIED_DIR must be absolute' >&2; exit 2 ;; esac
  input="$fixture/sample.xml"
  xsd="$fixture/extension.xsd"
  rules="$fixture/rules/sch/extTarget-6.0.sch"
  catalog="$fixture/model/xsd/xml-catalog.xml"
  for path in "$input" "$xsd" "$rules" "$catalog"; do
    if [ ! -r "$path" ]; then echo "Missing fixture file: $path" >&2; exit 2; fi
  done

  reject verify "$input" --schema "$xsd" --niem 6.0 --rules "$rules" --catalog "$catalog"
  grep -Fx "XSD validation: Passed ($xsd)" "$work/err"
  grep -Fx 'NIEM NDR: Unable to run' "$work/err"
  grep -Fx 'SCHEval executable not found on PATH' "$work/err"
  grep -Fx 'Hint: retry XSD-only verification by omitting --niem, --rules and --catalog.' "$work/err"
  cli verify "$input" --schema "$xsd" >"$work/out" 2>"$work/err"
  test ! -s "$work/err"
  grep -Fx "XSD validation: Passed ($xsd)" "$work/out"
  grep -Fx 'NIEM NDR: Not checked' "$work/out"
  check_clean
  exit 0
fi

if [ "$test_case" = recover ]; then
  demo="$root/examples/inventory"
  input="$demo/valid.xml"
  xsd="$demo/exchange.xsd"
  cli upload inventory "$xsd" >"$work/upload"
  cli switch inventory >"$work/switch"
  cp "$work/state/config.json" "$work/config-before"
  printf 'keep these bytes\n' >"$work/original"
  cp "$work/original" "$work/cwd/occupied.json"

  reject verify "$input" --schem "$xsd"
  grep -Fxq 'niemify: Unknown option: --schem' "$work/err"
  grep -Fq 'Usage: niemify verify <input.xml>' "$work/err"
  reject verify
  grep -Fq 'Usage: niemify verify <input.xml>' "$work/err"
  reject verify missing.xml --schema "$xsd"
  grep -Fq 'missing.xml:' "$work/err"
  grep -Fq 'Hint: check the input path' "$work/err"
  reject verify "$input" --schema missing.xsd
  grep -Fq 'Schema file not found: missing.xsd' "$work/err"
  reject convert "$input" occupied.json --schema inventory
  grep -Fxq 'niemify: Output already exists: occupied.json' "$work/err"
  grep -Fq 'choose another output path, or use - for stdout' "$work/err"
  cmp "$work/original" "$work/cwd/occupied.json"

  cli verify "$input" --schema "$xsd" >"$work/out" 2>"$work/err"
  test ! -s "$work/err"
  grep -Fxq "XSD validation: Passed ($xsd)" "$work/out"
  cli verify "$input" >"$work/out" 2>"$work/err"
  test ! -s "$work/err"
  grep -Fxq "XSD validation: Passed ($xsd)" "$work/out"
  cli convert "$input" retry.json --schema inventory >"$work/out" 2>"$work/err"
  test ! -s "$work/out"
  grep -Fxq 'Wrote retry.json (XML to JSON).' "$work/err"
  test -s "$work/cwd/retry.json"
  cmp "$work/original" "$work/cwd/occupied.json"
  cmp "$work/config-before" "$work/state/config.json"
  echo 'recover: five failures on stderr, occupied bytes and schema unchanged, valid retries passed'
  exit 0
fi

if [ "$test_case" = command-typo ]; then
  for typo in verfiy verfy verifyy verifx; do
    reject "$typo" missing.xml
    grep -Fxq "niemify: Unknown command: $typo. Did you mean \"verify\"?" "$work/err"
    cp "$work/err" "$work/execution-error"
    reject help "$typo"
    cmp "$work/execution-error" "$work/err"
    reject "$typo" --help
    cmp "$work/execution-error" "$work/err"
  done
  reject unrelated
  grep -Fxq 'niemify: Unknown command: unrelated. Run niemify --help.' "$work/err"
  reject help unrelated
  grep -Fxq 'niemify: Unknown command: unrelated. Run niemify --help.' "$work/err"
  cli help verify >"$work/out" 2>"$work/err"
  test ! -s "$work/err"
  grep -Fq 'Usage: niemify verify <input.xml>' "$work/out"
  check_clean
  echo 'command-typo: four edit types suggest verify, unrelated input points to root help, corrected help succeeds'
  exit 0
fi

if [ "$1" = command-help ]; then
  for command in verify convert list upload update switch; do
    cli help "$command" >"$work/$command" 2>"$work/err"
    test ! -s "$work/err"
    cli "$command" --help >"$work/flag" 2>"$work/err"
    test ! -s "$work/err"
    cmp "$work/$command" "$work/flag"
  done
  check_clean

  grep -Fxq 'Usage: niemify verify <input.xml> [--schema <name|path>] [--niem 6.0 --rules <file> [--catalog <file>]]' "$work/verify"
  grep -Fq 'saved schema name or local XSD path' "$work/verify"
  grep -Fq 'active schema (exchange-demo on a fresh configuration)' "$work/verify"
  grep -Fq 'By default, verify checks XML syntax and XSD validity only.' "$work/verify"
  awk '
    /^  niemify verify examples\/inventory\/valid[.]xml --schema examples\/inventory\/exchange[.]xsd$/ { xsd = NR }
    /^  niemify verify .* --niem 6[.]0 / { niem = NR }
    END { exit !(xsd && xsd < niem) }
  ' "$work/verify"
  grep -Fq -- '--rules rules/sch/extTarget-6.0.sch --catalog model/xsd/xml-catalog.xml' "$work/verify"
  grep -Fq 'Use - for data-only stdout.' "$work/convert"
  grep -Fq 'niemify convert exchange.xml exchange.json' "$work/convert"
  grep -Fq 'niemify convert exchange.json -' "$work/convert"
  grep -Fq 'List built-in and registered schema names as JSON without changing the configuration.' "$work/list"
  grep -Fq 'Save a new name for a trusted local XSD path without copying it.' "$work/upload"
  grep -Fq 'Replace an existing registration with a reference to a trusted local XSD without copying it.' "$work/update"
  grep -Fq 'default for later verify runs without --schema' "$work/switch"
  echo 'command-help: matching help forms, ordered verify examples, conversion and schema guidance, no external commands or local writes'
  exit 0
fi

cli >"$work/bare" 2>"$work/err"
test ! -s "$work/err"
cli --help >"$work/flag" 2>"$work/err"
test ! -s "$work/err"
cmp "$work/bare" "$work/flag"
check_clean

awk '
  /^Examples .*checkout/ { examples = NR }
  /^  niemify verify examples\/inventory\/valid[.]xml --schema examples\/inventory\/exchange[.]xsd$/ { verify = NR }
  /^  niemify convert examples\/inventory\/valid[.]xml -$/ { convert = NR }
  /^  niemify list$/ { list = NR }
  /^Convert and validate$/ { validation = NR }
  /^Manage local schemas$/ { schemas = NR }
  END { exit !(examples && examples < verify && verify < convert && convert < list && list < validation && validation < schemas) }
' "$work/bare"
grep -Fq 'niemify help <command>' "$work/bare"
grep -Fq 'niemify <command> --help' "$work/bare"
echo 'root-help: identical examples-first help, no external commands or local writes'
