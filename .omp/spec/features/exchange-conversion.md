# Convert an exchange between XML and JSON

## Outcome and scope

An integration developer can inspect or transform a local XML exchange as an ordered JSON document and serialize it back to XML. The CLI and Lua API expose the same conversion outcome. This is not NIEM JSON mapping, byte-for-byte XML reproduction, or NDR evaluation. The [conformance spec](niem-conformance.md) owns verification verdicts; the [CLI usability spec](cli-usability.md) owns help and terminal presentation.

## Beginning-to-end flow

1. With NIEMify installed, run `niemify convert input.xml output.json` or `niemify convert input.json output.xml`. The source extension selects direction; the destination may be a new file or `-` for stdout. An unsupported source extension is rejected. The in-process equivalents are `require('niemify').xml`, `.json`, and `.convert`; `.validate` returns `true` or raises an error using the same conversion checks.
2. XML is represented by an `elements` array: ordered siblings, repeated elements, mixed text, qualified names, namespace declarations, and attributes are preserved. The serializer can also consume a plain Lua table or JSON object; the Lua API can use `rootElement` and `namespace` for that shorthand. This representation does not preserve exact source formatting. DTDs and malformed input are rejected.
3. Optionally select a [registered XSD](schema-management.md) with `--schema <name>`; conversion does not accept an unregistered XSD path. The Lua API can also request the active schema with `validate = true`. Without either opt-in, conversion does not require `xmllint`. Validation runs before publication: failure does not create a destination or expose partial output. Existing files are not replaced; the caller owns the source and chooses an unused destination or stdout.

## Acceptance cases

| Case | Start and action | Observable result | Status |
|---|---|---|---|
| AC1 — Convert both ways | Lua 5.4 and local dependencies; convert the [inventory sample](../../../examples/inventory/valid.xml) to JSON and back, using the registered inventory schema | JSON has the `warehouse` attribute and preserves the original qualified names, including `common:Sku`; the SKUs are `BOX-0007`, then `TAP-0012`. The returned XML validates against the same local XSD. | Verified — baseline Ubuntu CI |
| AC2 — Embed conversion | From Lua, convert mixed XML with repeated elements, namespace declarations and CDATA; render an independently specified ordered tree and reparse it | Returned Lua values retain element order and mixed content; reparse equals the expected document structure, not source bytes. Invalid JSON trees such as two-root documents raise an error. | Verified — baseline Ubuntu CI |
| AC3 — Recover without losing data | Convert with a named XSD using the [bad SKU fixture](../../../examples/inventory/invalid.xml); then try to convert valid data to an occupied destination and retry at a new path | Invalid input exits nonzero without creating a file. An occupied destination is refused without modifying its bytes. The valid retry writes the requested file. | Implemented — unverified as a combined recovery scenario |

## Status and evidence

The [Lua API](../../../niemify/init.lua), [converter](../../../niemify/converter.lua), and [CLI](../../../bin/niemify) implement this workflow. [Ubuntu GitHub Actions, 2026-11-20 UTC, `9f93b40064`](https://github.com/ObsaSiyo/niemify/actions/runs/44669729411) ran the [Lua converter tests](../../../tests/converter.lua) and [CLI round-trip and rejection checks](../../../tests/run.sh). The CLI suite checks overwrite refusal and separate successful conversions; it does not compare the occupied file byte-for-byte after refusal and then exercise recovery in the same case.
