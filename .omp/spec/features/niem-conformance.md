# NIEM exchange conformance check

## Outcome and scope

An integration developer receives an existing NIEM XML exchange and checks a sample locally in one `verify` invocation. The CLI shows what was checked, against which artifact, and what requires review. No configuration or registration is necessary for a one-off check.

This feature consumes a trusted local XML instance, an entry XSD and its local dependencies. The first NIEM-aware profile checks the **NIEM 6.0 extension schema document** against a pinned subset of automated Naming and Design Rules (NDR). It does not assert that the XML message, the whole schema set, or an IEPD is NIEM-conformant. Out of scope: exchange design and mapping, CMF authoring, NIEM JSON translation, IEPD packaging, automatic downloads, certification, and arbitrary Schematron/XSLT execution by the CLI.

## Beginning-to-end flow

1. From any working directory, the developer runs `niemify verify message.xml --schema ./exchange/message.xsd`. Lua and `xmllint` are the only prerequisites for this basic path. An explicit local XSD path is resolved from the working directory; its imports/includes resolve from their owning schema files. Saved names and the active schema remain supported. A path-like selector (a slash, an absolute path, or `.xsd` suffix) is treated as a path, even if missing; do not retry it as a schema name.
2. Report separate results for `XML syntax`, `XSD validation`, and `NIEM NDR`. The normal success is `Well-formed` / `Passed` / `Not checked`, with the selected schema identity. Distinguish malformed XML, XSD rejection, and unavailable or unresolved schema dependencies. Use the original message path rather than a staging filename; include a file/line and a reason when the engine reports them. Write the result to stdout on success and the failure report to stderr. Exit zero only when all requested automated checks ran and passed; failures and inability to run are nonzero and have distinct report states.
3. With an NIEM 6.0 **extension** entry schema, optionally add `--niem 6.0 --rules ./ndr/sch/extTarget-6.0.sch` and, when needed by a rule, `--catalog ./exchange/xml-catalog.xml`. The optional path requires the pinned local NIEMOpen rule tree, including its relative includes, and `scheval` on PATH. `--catalog` supplies a local catalog to the NDR evaluator, not to the basic XSD step. No silent legacy or alternative-target fallback. Validate the entry XSD's effective CTAS attribute by namespace URI and target identifier; a declaration selects scope, not proof of conformance. Unsupported or absent targets cannot silently pass.
4. After syntax and XSD validation pass, run the pinned NDR profile on the entry XSD, not on the XML instance or every imported document. Present automated `Passed`, `Failed`, or `Unable to run`, plus the profile, target, rule provenance, diagnostic IDs/severities, and `Manual review still required` whenever the profile is evaluated. An automated pass must not turn warnings into failures or hide them. A rule failure cannot be inferred from subprocess exit alone until the pinned tool's contract is verified. A malformed, partial, unexpected, or interrupted report must not look like a clean run.
5. The developer can correct the input or dependencies and retry. The CLI does not modify source files, register a path, change the active schema, save reports, transmit payloads, or fetch prerequisites. Test network-denied execution with the pinned engine and catalog. Keep the NIEM-aware path explicitly unavailable if external resolution cannot be prevented or the tool/rule combination cannot be verified.

## What NIEMOpen provides

| Resource | Use in this feature |
|---|---|
| [NIEM Model 6.0](https://docs.oasis-open.org/niemopen/niem-model/v6.0/os/niem-model-v6.0-os.html) | Official Core, domain and utility schemas, and an XML catalog; use real Core reuse in the synthetic acceptance fixture. |
| [NDR 6.0 §§6.1–6.3](https://docs.oasis-open.org/niemopen/ndr/v6.0/os/niem-ndr-v6.0-os.html#61-conformance-targets) | Target definitions, CTAS assertions, automated coverage boundaries, and rules requiring human evaluation. The standard's §6.3 does not resolve an automated-rule release pointer. |
| [NIEMOpen extension Schematron candidate](https://github.com/niemopen/niem-naming-design-rules/tree/33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817/sch) and [SCHEval](https://github.com/niemopen/cmftool/tree/main/app-scheval) | Candidate rule tree pinned to a repository commit, not a claim of full OASIS rule coverage; SCHEval supports Schematron, diagnostics, SVRL and an optional catalog. The [v1.2.1 distribution](https://github.com/niemopen/cmftool/releases/tag/v1.2.1) publishes `scheval-1.2.zip`. Enable only after the candidate and actual distribution are qualified together. |
| [NIEMOpen CMFTool](https://github.com/niemopen/cmftool) and [exchange lifecycle guidance](https://niem.github.io/reference/iepd/lifecycle/) | Help authors build and package an exchange upstream. Link these from user documentation; do not duplicate model generation, translation, or IEPD review. |

## Acceptance cases

All new cases are **Planned**. Use non-sensitive synthetic data and isolated temporary directories; no live accounts or provider writes.

### AC1 — Check an existing exchange without registration

- **Environment and fixture:** macOS or Linux, Lua and `xmllint`, fresh `NIEMIFY_HOME`; [valid inventory XML](../../../examples/inventory/valid.xml) with [entry XSD](../../../examples/inventory/exchange.xsd) and a relative imported schema.
- **Action:** Run the basic one-off command from a different working directory. Repeat with a registered name using isolated state.
- **Observable result:** Both pass and name the selected XSD; NDR is `Not checked`. The one-off path leaves the config and source files unchanged.

### AC2 — Diagnose and recover from invalid input or missing schema dependencies

- **Environment and fixture:** Same environment; [bad SKU sample](../../../examples/inventory/invalid.xml), malformed XML, and a copied schema tree with its required local import removed.
- **Action:** Check each input, then restore the import and check the valid sample.
- **Observable result:** Bad SKU reports syntax passed and XSD failed with its diagnostic, original path and line if available. Malformed input skips XSD. The missing import is reported as unable to validate, not a bad message or a schema name. Restoring it passes. No case modifies files or implies NDR was checked.

### AC3 — Check a NIEM 6 extension with upstream tools

- **Environment and fixture:** Linux, pinned SCHEval and rule tree, network denied; a synthetic NIEM 6 extension with real Core reuse, valid sample and local dependencies/catalog. Independently reviewed rule applicability and an extension variant that still validates its XML sample but triggers a known mandatory rule.
- **Verified — installed rock, network-denied Linux aarch64, 2026-11-20 UTC:** [Acceptance run](../../tasks/niem-conformance.md#L93): both entries passed XSD; the clean entry passed NDR and the negative entry failed with the same 9-94 diagnostic as direct SCHEval. The [direct qualification](../../../tests/fixtures/niem6-extension/README.md#scheval-qualification--2026-11-20-utc) separately verified warning-only classification.
- **Action:** Run the documented opt-in command on both bundles and independently run the same pinned SCHEval rules directly on each entry schema.
- **Observable result:** The clean case shows XSD passed, automated NDR passed, and manual review required; it does not claim certification or package/message conformance. The rule-failure case still shows XSD passed, reports the same mandatory rule ID and diagnostic as direct SCHEval, and exits nonzero. Warnings remain visible without failing the run by themselves. Record the exact rule tree revision, engine distribution and environment.

### AC4 — Refuse an unchecked or unavailable conformance run

- **Environment and fixture:** Isolated PATH/config; a missing executable, missing or mismatched rule tree, an XSD with an absent or unsupported CTAS target, and a failed/partial evaluator report.
- **Action:** Request the NIEM check for each case, then retry the same message without `--niem`.
- **Observable result:** Each requested but unavailable check is nonzero, states what blocked it and how to recover, and never reports automated NDR passed. The XML/XSD-only retry still works without Java and explicitly reports NDR not checked. No automatic network retrieval occurs.
- **Verified — focused tests:** [Target and report tests](../../../tests/ndr.lua) reject missing or unsupported targets and malformed, incomplete or contradictory SVRL. The [checkout CLI test](../../../tests/verify.sh) refused missing rules, and the installed XSD-only retry worked without an evaluator.

### AC5 — Follow the instructions from a fresh checkout

- **Environment and fixture:** Fresh checkout plus documented tool prerequisites and synthetic samples; separately try basic mode without Java.
- **Action:** Follow help and README for basic validation, optional NIEM validation, and the documented rule-check failure.
- **Observable result:** Commands and reported meanings match observed results; links distinguish a schema validity checker from NIEM conformance tools. The docs identify the supported target, version/pin, manual checks, and limits without suggesting NIEM JSON output or a blanket pass.

## Status and evidence

- **Verified — Ubuntu GitHub Actions, 2026-11-20 UTC, revision `9f93b40064`:** [Passing baseline run](https://github.com/ObsaSiyo/niemify/actions/runs/44669729411) covers named XSD validation and rejection, local relative imports, and XML tree conversion.
- **Verified — installed rock, network-denied Linux aarch64, 2026-11-20 UTC:** The [release acceptance](../../tasks/niem-conformance.md#L93) exercised the [documented basic and opt-in commands](../../../README.md#check-an-existing-exchange). It verifies the pinned automated profile on the synthetic fixture, not full NIEM conformance.

## Open decision

Promote the pinned candidate rule tree only after confirming rule and dependency coverage for the selected extension target, diagnostic/exit meanings, license/provenance for any redistributed material, and network-denied execution. If that fails, keep XSD-only `verify` as the runnable product and document the NDR check as unavailable rather than advertising conformance.
