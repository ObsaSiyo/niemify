# Schema management tasks

Source: [Save and reuse local schemas](../spec/features/schema-management.md).

AC1 (registered schema reuse) and AC2 (switch/update through the Lua registry API) have [recorded baseline evidence](../spec/features/schema-management.md#status-and-evidence).

- [x] **schema-management-01 Verify rejected registry writes preserve configuration**
  - Source: [AC3 — Refuse unsafe replacement](../spec/features/schema-management.md#acceptance-cases)
  - Depends on: none
  - Change: Verification only. In a temporary `NIEMIFY_HOME`, register and activate a synthetic schema, then snapshot `config.json`. Use the checkout CLI and two readable local fixture XSDs; do not edit product code.
  - Done when: A duplicate upload, an update of built-in `exchange-demo`, and an update of the saved name to a missing path each exit nonzero and leave config byte-identical. A valid replacement changes only the saved path; the active name persists in a separate CLI invocation.
  - Verify: From the checkout using `lua5.4 bin/niemify`, run `upload`, `switch`, each rejected mutation, and a valid `update`. Capture statuses, compare the config with `cmp` after each rejection, and compare decoded `config` output before and after the valid update.
  - Evidence: 2026-11-20, macOS arm64, Lua 5.4.9. With a disposable `NIEMIFY_HOME`, ran `lua5.4 bin/niemify upload inventory` for `examples/inventory/exchange.xsd`, then `switch inventory`. A duplicate upload, a built-in `exchange-demo` update, and an update of `inventory` to a missing XSD each exited 1 with empty stdout and a distinct stderr diagnostic. `cmp` confirmed `config.json` remained byte-identical after each rejection. A valid `update inventory` to `niemify/exchange-demo.xsd` exited 0. Decoded `config` output from separate invocations confirmed only `schemas.inventory.path` changed and `activeSchema` remained `inventory`.
