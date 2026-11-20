# Synthetic NIEM 6 extension fixture

Both entry schemas validate the same non-nil `sample.xml`. They import the official NIEM Core 6.0 `nc:ActivityName` global element and derive `ActivityNoticeType` from `structures:ObjectType`. The `example.org` namespace, notice type and sample are original synthetic material under the repository’s [MIT license](../../../LICENSE).

[`extension.xsd`](extension.xsd) is the clean candidate. [`extension-rule9-94.xsd`](extension-rule9-94.xsd) changes only `ActivityNotice/@nillable` from `true` to `false`. The sample never sets `xsi:nil`, so that change does not affect its XSD validity. [OASIS NDR 6.0 rule 9-94](https://docs.oasis-open.org/niemopen/ndr/v6.0/os/niem-ndr-v6.0-os.html#rule9-94) requires `nillable=true` for extension element declarations. The [pinned Schematron pattern `rule9-94`](https://github.com/niemopen/niem-naming-design-rules/blob/33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817/sch/rule/9-94.xml) is included by that revision’s `sch/extTarget-6.0.sch`. The XSD checks below do not run Schematron or establish NDR conformance.

## Prepare and check the local fixture

From the repository root, stage a disposable copy and acquire the [OASIS NIEM Model 6.0 OASIS Standard archive](https://docs.oasis-open.org/niemopen/niem-model/v6.0/os/niem-model-v6.0-os.zip). Verify the archive before unpacking the `xsd/` tree unchanged under `model/`. Imports resolve by relative path; no XML catalog is needed for these XSD checks.

```sh
set -eu
work=$(mktemp -d)
cp tests/fixtures/niem6-extension/*.xsd tests/fixtures/niem6-extension/sample.xml "$work/"
cd "$work"
curl -fL 'https://docs.oasis-open.org/niemopen/niem-model/v6.0/os/niem-model-v6.0-os.zip' -o model.zip
printf '%s  %s\n' 2b899067b5312333935329e6e7665e1eb295f392a51d4a56bc9800dbcc42fcfa model.zip | shasum -a 256 -c
unzip -q model.zip 'xsd/*' -d model
xmllint --nonet --nocatalogs --noout --schema extension.xsd sample.xml
xmllint --nonet --nocatalogs --noout --schema extension-rule9-94.xsd sample.xml
```

No upstream XSD, catalog, or rule files are redistributed here. The Core and structures members of the pinned archive carry OASIS Open copyright and CC BY 4.0 notices; those members retain their PS02 headers in the OASIS Standard archive. Keep upstream notices intact, including those on transitive dependencies.

| File | SHA-256 |
|---|---|
| `model.zip` | `2b899067b5312333935329e6e7665e1eb295f392a51d4a56bc9800dbcc42fcfa` |
| `model/xsd/niem-core.xsd` | `b35ef8938dead814b6964e8a8a4a74091a990da73520a7ac7d0d5676148c3065` |
| `model/xsd/utility/structures.xsd` | `3b65a303a8c790b7e8b2f5250afa52653a031f8612676d33029da9afde36a3ab` |
| Pinned `sch/rule/9-94.xml` | `6501d7811bed37b5712aa622ec3ea21f1573e1e5bae28d212111726d0f775358` |
| `extension.xsd` | `32dd46df0ae3c355b0181a3e703e8e2c89a914f24ac8e4708c70a79c4818c0f0` |
| `extension-rule9-94.xsd` | `61975380e611a9770e28acc37efaefbb48c20d1d69eaff5b6988fd89e42affae` |
| `sample.xml` | `6de16d52c0b1af628e2b0533a901a0ac152ad91032486c77c4af76373807c6e4` |

## SCHEval qualification — 2026-11-20 UTC

Qualified the [upstream v1.2.1 release asset `scheval-1.2.zip`](https://github.com/niemopen/cmftool/releases/tag/v1.2.1), SHA-256 `f0ae84720a6f361269b0fee4f711f6ccfc849a3dce5ded4caacaf1aa553ab42a`, with the full `sch/` tree from [commit `33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817`](https://github.com/niemopen/niem-naming-design-rules/tree/33ed73c4b3f5e305b4c6cdb2d35e8ef09ced7817/sch). The codeload tarball SHA-256 was `50f6148758154a4b088c9787afab8c0fc845be1b385ce6f9591308e4034fc0db`. From the extracted rules checkout, `find sch -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256` produced `60067e43742bd93aad7ff70c7a72d4fb356a99fc95ac3893f5b06ffe73475c0e`. This covers the entry file and transitive includes; do not pin only the entry file. The upstream catalog and schemas came from the verified model archive above.

Runtime: Linux aarch64, Temurin 25.0.5+8, image `eclipse-temurin@sha256:945247f9d092703e0c6be92243ef3c51640229e23ab34d353c8dcdc73e6cd4e6`. Java 21 could not load the release (class-file version 69.0 requires Java 25). Run the unpacked launcher via `sh` if it lacks an execute bit.

Stage `engine/scheval-1.2/`, `rules/sch/`, and `model/xsd/` next to the entry schemas. Preload the pinned image separately. Docker used `--pull=never --network=none --cap-drop=ALL --security-opt=no-new-privileges --read-only --tmpfs /tmp`, with only the staged directory bind-mounted read-only at `/fixture` and used as the working directory. `/sys/class/net` contained only `lo`. From inside the container:

```sh
sh engine/scheval-1.2/bin/scheval --svrl --schema rules/sch/extTarget-6.0.sch \
  --catalog model/xsd/xml-catalog.xml --output /tmp/report.xml extension.xsd
```

Use a fresh output file for each invocation. Report XML and process logs are separate; stdout in this environment included a Java hostname diagnostic before any SVRL when stdout was used as the report destination.

| Case | Exit with `--output` | Observed report |
|---|---:|---|
| `extension.xsd` with catalog | 0 | Complete SVRL; no failed assertions or successful reports |
| `extension-rule9-94.xsd` with catalog | 0 | Complete SVRL; exactly one failed assertion, `Rule 9-94`, for the non-nillable declaration |
| Clean candidate with an XML comment immediately inside `xs:schema`, with catalog | 0 | Complete SVRL; only `Rule 9-21`, a `successful-report` with `role="warning"` |
| Catalog omitted | 1 | No complete report; transitive type lookup failed with `$xml-catalog is not set` |
| Nonexistent catalog path | 2 | No complete report; missing catalog diagnostic |

With stdout output instead of `--output`, omitting the catalog yielded exit 0 and no complete SVRL. A successful process exit does not establish a clean evaluation. Require a complete SVRL document from the dedicated output path; preserve warning reports, and use failed assertions to distinguish rule failures. No evaluator, rules, or upstream report output is checked in. This qualifies the fixture/tool combination only, not the NIEMify CLI or any deployed sandbox.
