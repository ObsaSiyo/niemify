# Exchange conversion tasks

Source: [Convert an exchange between XML and JSON](../spec/features/exchange-conversion.md).

AC1 (two-way conversion) and AC2 (Lua embedding) have [recorded baseline evidence](../spec/features/exchange-conversion.md#status-and-evidence); no new implementation cards are needed for them.

- [x] **exchange-conversion-01 Verify that failed conversions leave files intact**
  - Source: [AC3 — Recover without losing data](../spec/features/exchange-conversion.md#acceptance-cases)
  - Depends on: none
  - Change: Verification only. Use a disposable directory and `NIEMIFY_HOME` with the synthetic inventory XSD and its import registered as `inventory`. Use the checkout CLI; do not change product code.
  - Done when: The bad SKU fails nonzero without creating the requested output. Converting valid input to a preexisting sentinel file fails nonzero and leaves its bytes unchanged. Retrying valid input to a new path writes JSON with both expected SKUs in order.
  - Verify: From the checkout with Lua 5.4 dependencies and `xmllint`, register the inventory XSD, then run `lua5.4 bin/niemify convert <input> <destination> --schema inventory` for all three cases. Capture exit statuses, compare the sentinel with `cmp`, and decode the new JSON to check `BOX-0007`, then `TAP-0012`.
  - Evidence: 2026-11-20, macOS arm64, Lua 5.4.9 and `xmllint` (libxml 2.9.13), from the checkout with a disposable `NIEMIFY_HOME`. Registered `examples/inventory/exchange.xsd` as `inventory`, then ran `lua5.4 bin/niemify convert <input> <destination> --schema inventory` for all three cases. The bad SKU `box-7` exited 1 and created no destination; valid input to an occupied destination exited 1 and `cmp` confirmed the binary sentinel was unchanged. Retrying at a new path exited 0; `dkjson` decoded `BOX-0007`, then `TAP-0012`. The sentinel still matched after the retry.
