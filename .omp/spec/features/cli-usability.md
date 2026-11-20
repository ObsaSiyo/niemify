# Discover and use the NIEMify CLI

## Outcome and scope

A first-time integration developer can discover, run, and recover from the common `niemify` workflows without opening a browser. An existing shell script can keep using the same commands and machine-readable output. The feature is a Lua CLI presentation and diagnostics change: no npm/Bun runtime, npm package publication, interactive wizard, schema-rule changes, or new config format. The [NIEM conformance spec](niem-conformance.md) owns XSD/NDR validation behavior and prerequisites.

## Reference patterns

| Reference | Apply to NIEMify |
|---|---|
| [npm CLI](https://docs.npmjs.com/cli/v11/commands/npm/) and [npm help](https://docs.npmjs.com/cli/v11/commands/npm-help/) | Lead with a short list of runnable examples. Offer a command-specific help path and a quick help flag. |
| [Bun CLI overview](https://bun.com/docs/runtime) and [Bun command examples](https://bun.com/docs/pm/cli/install) | Group commands by user goal and put concrete examples next to their purpose. Keep the shortest useful invocation easy to scan. |

These are interaction references, not adoption of package-manager commands or dependencies. The [existing NIEMify CLI design](../../../design-system/README.md) provides local examples of command, result, and recovery surfaces.

## Beginning-to-end flow

1. **Discover.** From any working directory, `niemify` or `niemify --help` shows what the tool does, with commands grouped by outcome: validate/convert and manage local schemas. Put three common jobs first: verify against an explicit local XSD, convert XML to JSON, and list available schemas. Root help states which examples use checkout fixtures and how to get command help. Help works with no configured schema and no evaluator installed.
2. **Act.** `niemify help verify` and `niemify verify --help` show the same usage: required operands, meaningful defaults, supported flags, and a copyable XSD-only example before the opt-in NIEM example. `convert` help shows both directions and `-` for data-only stdout. Schema-management help distinguishes `list` (available names), `upload`/`update` (store a reference to a trusted local XSD), and `switch` (change the default for later invocations). Preserve the existing commands, options, and persisted `NIEMIFY_HOME` behavior.
3. **Recover.** Invalid commands or options, missing operands, and common workflow failures tell the user what failed and how to recover. An unknown command suggests a correction only when there is a unique close command name (one character inserted, deleted, substituted, or transposed); otherwise point to root help. Suggestions are never executed. Missing inputs and schema dependencies name the affected path; existing output names the destination and offers an alternate path or stdout; an unavailable optional NDR check distinguishes setup failure from a rule failure and tells the user how to retry XSD only. Do not silently retry, overwrite, register a schema, or change the active schema.
4. **Use the result.** A file conversion confirms the actual output path on stderr. Plain help and verification reports remain readable in a redirected stream. For `convert … -`, stdout remains payload only; failures go to stderr with nonzero exit and no partial payload. Any optional color is restricted to human-facing TTY output and disabled by `NO_COLOR`. No progress spinners or interactive confirmations enter a pipeline.

## Acceptance cases

| Case | Environment and start state | User action | Observable result |
|---|---|---|---|
| AC1 — Find a starting command | Installed Lua CLI; fresh temporary `NIEMIFY_HOME`; `xmllint`, Java, and SCHEval absent from `PATH` | Run bare `niemify`, `niemify --help`, `niemify help verify`, and `niemify verify --help` | Both root invocations exit zero and put the same grouped help and examples on stdout. Both command-help forms match and show the required input, local XSD and saved-name choices, and opt-in NIEM flags. No config writes or prerequisite probes. |
| AC2 — Verify without setup | macOS or Linux with Lua and `xmllint`; fresh `NIEMIFY_HOME`; the [synthetic XML](../../../examples/inventory/valid.xml) and [entry XSD](../../../examples/inventory/exchange.xsd) with its sibling import | Run the root-help XSD-only example from the checkout, then rerun from another directory using absolute input paths | Both runs exit zero and show well-formed XML, XSD passed with entry path, and NDR not checked. Source and config remain unchanged; no Java or SCHEval necessary. |
| AC3 — Correct a failed command | Isolated cwd with a valid fixture, a missing schema path, and a preexisting output | Run `niemify verfiy`, an unknown name with no close match, `niemify verify` without input, verification with a missing XSD, and conversion to the preexisting output. Follow the valid recovery for each. | Original failures exit nonzero with empty stdout. `verfiy` suggests `verify`; the distant name points to root help; missing input points to command usage; the missing XSD names the path; existing output names the file and leaves its bytes unchanged. Corrected invocations work; none of the original failures runs the suggested operation. |
| AC4 — Preserve scripting behavior | Redirected stdout/stderr; existing schema and the synthetic inventory fixtures; repeat with `NO_COLOR=1` in a TTY | Convert valid XML to `-`, convert invalid XML to `-` with validation, and convert valid XML to a new output file | Stdout of the successful pipe parses as JSON and retains both expected inventory items in order. The invalid pipe exits nonzero with empty stdout. File conversion produces the output and puts its receipt on stderr. No ANSI decoration in redirected output or with `NO_COLOR=1`. |
| AC5 — Recover from an unavailable optional check | Valid qualified NIEM fixture in isolated Linux with the evaluator unavailable | Request NIEM verification, then follow the suggested XSD-only retry | Original invocation distinguishes `Unable to run` from `Failed`, names the missing prerequisite, and exits nonzero. The retry passes XSD and explicitly reports NDR not checked. Rule-failure and sandbox acceptance are defined in the [conformance spec](niem-conformance.md). |

## Status and evidence

- **Implemented — baseline only:** [`bin/niemify`](../../../bin/niemify) already has grouped help, both command-help forms, file receipts, output protection, and explicit XSD-only and opt-in verification paths. [`tests/run.sh`](../../../tests/run.sh) and [`tests/verify.sh`](../../../tests/verify.sh) contain existing CLI coverage. They are not evidence for the new help and recovery behavior.
- **Verified — baseline, network-denied Linux aarch64, 2026-11-20 UTC:** The [installed-rock acceptance](../../tasks/niem-conformance.md#L93) exercised the existing basic and opt-in paths, including the Java-free basic example. See the [current usage guide](../../../README.md#convert-and-verify) for what ships today.
- **Planned — AC1–AC5 for the revised CLI:** No revised help, typo recovery, or terminal/pipeline behavior has been exercised. Verify from an installed package in a fresh environment, including redirected machine output and the unavailable-NDR retry.
