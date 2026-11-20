# CLI usability tasks

Source: [Discover and use the NIEMify CLI](../spec/features/cli-usability.md).

- [x] **cli-usability-01 Put copyable examples first in root help**
  - Source: [AC1 — Find a starting command](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: none
  - Change: Update root help in `bin/niemify` to lead with explicit-XSD verification, XML-to-JSON conversion, and listing schemas. Keep existing command groups and show how to open command help; label examples that need checkout fixtures. Start `tests/cli-usability.sh` with a `root-help` case using a clean config and an isolated PATH.
  - Done when: Bare invocation and `--help` exit zero, print identical output with the three examples ahead of grouped commands, and need no config, `xmllint`, Java, or SCHEval. No writes or prerequisite probes during help.
  - Verify: `sh tests/cli-usability.sh root-help` from the checkout with Lua 5.4 and its rock dependencies available to the harness.
  - Evidence: 2026-11-19, macOS arm64, Lua 5.4.9 from the checkout: `sh tests/cli-usability.sh root-help` passed. Bare and `--help` exited zero with identical stdout and empty stderr; the checkout-labeled examples preceded both command groups. With an empty PATH directory and external command calls rejected, neither invocation probed prerequisites or created config or working-directory files.

- [x] **cli-usability-02 Make command help answer what to run next**
  - Source: [AC1 — Find a starting command](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: `cli-usability-01`
  - Change: Update the `bin/niemify` command-help entries and renderer. Put verify’s XSD-only example before its opt-in NIEM example; show both convert directions and `-`; clarify how list/upload/update/switch affect saved schemas. Keep help entry points and existing flags. Add a `command-help` case to `tests/cli-usability.sh`.
  - Done when: `help verify` and `verify --help` return identical descriptions of operands, schema choices, defaults and supported NIEM flags. Convert and schema-management help show the documented actions without touching files or invoking validators.
  - Verify: `sh tests/cli-usability.sh command-help` from the checkout with Lua 5.4 dependencies and no external evaluator on PATH during CLI execution.
  - Evidence: 2026-11-19, macOS arm64, Lua 5.4.9 from the checkout: `sh tests/cli-usability.sh command-help` passed. Both help forms matched for verify, convert, list, upload, update, and switch, with empty stderr. Verify showed its operands, schema choices, default and NIEM flags, with the XSD-only example first. Conversion and schema guidance passed with empty PATH, external command calls rejected, and no config or working-directory files created. `sh tests/cli-usability.sh root-help` also passed after the harness change.

- [x] **cli-usability-03 Suggest a command only for a unique typo**
  - Source: [AC3 — Correct a failed command](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: `cli-usability-02`
  - Change: In `bin/niemify`, use the actual command names to suggest a unique one-edit correction (insert, delete, substitute, or transpose adjacent characters). Use the same diagnostic for execution and help. For distant or ambiguous input, point to root help. Add a `command-typo` case to `tests/cli-usability.sh`.
  - Done when: `verfiy` suggests `verify` without executing it, an unrelated or ambiguous spelling gets no command suggestion, and a corrected help invocation works. Errors have nonzero exits, stderr diagnostics, and empty stdout.
  - Verify: `sh tests/cli-usability.sh command-typo` from the checkout without external validators.
  - Evidence: 2026-11-19, macOS arm64, Lua 5.4.9 from the checkout: `sh tests/cli-usability.sh command-typo` passed on an isolated PATH with external command calls rejected. All four edit types suggested `verify` with matching execution and help diagnostics, nonzero exit, and empty stdout. Unrelated input pointed to root help without a suggestion; corrected help succeeded with no local writes. The current command names have no overlapping one-edit spellings, so ambiguous input was not exercised through the CLI.

- [x] **cli-usability-04 Give a recovery step for usage and file errors**
  - Source: [AC3 — Correct a failed command](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: `cli-usability-03`
  - Change: In `bin/niemify`, make invalid options and missing operands point to relevant usage; keep input and schema path diagnostics and the existing overwrite refusal. Add a `recover` case to `tests/cli-usability.sh`; reuse the local inventory fixture and import dependencies without changing validation logic.
  - Done when: Invalid option, absent operand, missing input, missing XSD and occupied output all fail with empty stdout and actionable stderr. The occupied output keeps its original bytes, no active schema changes, and valid retries succeed.
  - Verify: `sh tests/cli-usability.sh recover` from the checkout with Lua 5.4 and `xmllint`.
  - Evidence: 2026-11-19, macOS arm64, Lua 5.4.9 and `/usr/bin/xmllint`: `sh tests/cli-usability.sh recover` passed from the checkout in a temporary working directory with an isolated PATH containing `xmllint`. All five failure cases exited nonzero with empty stdout and actionable stderr. The occupied output and saved configuration remained byte-identical. Explicit-XSD and active-schema verification passed with the inventory import, and conversion succeeded at a new path. `sh tests/cli-usability.sh command-typo` also passed after the shared harness change.

- [x] **cli-usability-05 Offer an XSD-only retry when NIEM checks are unavailable**
  - Source: [AC5 — Recover from an unavailable optional check](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: `cli-usability-04`
  - Change: Add an XSD-only retry hint to the `Unable to run` branch in `bin/niemify`; leave rule failures and verdicts unchanged. Add an `ndr-retry` case to `tests/cli-usability.sh` using the qualified model fixture from the [fixture setup](../../tests/fixtures/niem6-extension/README.md#prepare-and-check-the-local-fixture).
  - Done when: In network-denied Linux with valid XSD dependencies and no SCHEval on PATH, an opt-in request exits nonzero, names the missing evaluator, and states which flags to omit. Following the hint succeeds and prints `NIEM NDR: Not checked`, without writing config or fixtures.
  - Verify: `NDR_QUALIFIED_DIR=<absolute-staged-fixture-directory> sh tests/cli-usability.sh ndr-retry` from the checkout under the [documented isolation settings](../../tests/fixtures/niem6-extension/README.md#scheval-qualification--2026-11-20-utc), with Lua 5.4 and `xmllint` but no evaluator.
  - Evidence: 2026-11-19, Docker Linux aarch64, Lua 5.4.8 and `xmllint`, image `niemify-ndr-rock-local` (`2bc697b3cf4a`): `NDR_QUALIFIED_DIR=/fixture sh tests/cli-usability.sh ndr-retry` passed. Network disabled (only `lo`), all capabilities dropped, no new privileges, read-only root and checkout/fixture mounts, writable `/tmp`. With only `xmllint` on CLI PATH, the opt-in run failed with empty stdout after XSD passed, named missing SCHEval and gave the three-flag omission hint. The retry passed XSD and reported `NIEM NDR: Not checked`; no config was created and the fixture remained read-only.

- [x] **cli-usability-06 Verify help examples and automation with the installed CLI**
  - Source: [AC1 — Find a starting command, AC2 — Verify without setup, AC4 — Preserve scripting behavior](../spec/features/cli-usability.md#acceptance-cases)
  - Depends on: `cli-usability-05`
  - Change: Verification only. Install the current rock in a clean tree with the documented dependencies; exercise help and the inventory workflow with fresh `NIEMIFY_HOME`. Do not add color just to test `NO_COLOR`.
  - Done when: Both root and command help forms match their counterparts with external validators off PATH. With `xmllint` restored, the root verify example and its absolute-path rerun from another cwd pass without state or fixture writes. Valid piped JSON has both expected SKUs in order, rejected conversion emits no partial payload, and a file conversion receipt goes only to stderr. Redirected and `NO_COLOR=1` PTY runs are free of ANSI decoration.
  - Verify: From the checkout, install into a disposable tree with `luarocks --lua-version=5.4 --tree=<temp-tree> make niemify-2.0.0-1.rockspec`, then run the AC1, AC2 and AC4 invocations via the installed `niemify`; capture statuses, stdout/stderr, parsed payload and fixture/config state. Use a PTY for `NO_COLOR=1` and record its environment separately.
  - Evidence: 2026-11-20, macOS arm64, Lua 5.4.9, `xmllint` (libxml 2.9.13). `luarocks --lua-version=5.4 --tree=<temp-tree> make niemify-2.0.0-1.rockspec` installed the current rock with dkjson 2.11-1, luaexpat 1.5.2-1 and luafilesystem 1.9.0-1. With an empty PATH directory and fresh `NIEMIFY_HOME`, the installed root and verify help pairs exited 0, matched byte-for-byte within each pair, and had empty stderr. With only `xmllint` restored to PATH, the checkout example and absolute-path retry from another working directory exited 0 and reported well-formed XML, an XSD pass at the expected path, and `NIEM NDR: Not checked`. Neither help nor verification created configuration or changed fixtures. With inventory registered, valid conversion exited 0 with JSON containing `BOX-0007`, then `TAP-0012`; invalid conversion exited 1 with empty stdout and a diagnostic naming `box-7`; file conversion exited 0 with empty stdout, valid output, and its receipt only on stderr. Redirected streams contained no ANSI escapes; fixture and saved config bytes were unchanged.
  - PTY evidence: Same macOS/Lua install with `NO_COLOR=1`, `TERM=xterm-256color`, and stdin/stdout/stderr attached to a fresh PTY per run. Valid stdout and file conversions exited 0 and preserved SKU order; invalid conversion exited 1 with its diagnostic. Root help exited 0 and matched redirected help after normalizing PTY line endings. No ANSI escapes in any PTY capture.
