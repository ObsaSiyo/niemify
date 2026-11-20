# Save and reuse local schemas

## Outcome and scope

A developer who repeatedly processes an exchange can register a trusted local XSD once, reuse its name, and set a default for later invocations. This is a local path registry, not a schema upload service, repository, or remote catalog. One-off path validation and NDR result semantics are covered by the [conformance spec](niem-conformance.md).

## Beginning-to-end flow

1. Use `niemify list` to see built-in and saved names and `niemify config` to inspect the active name and registrations. A fresh configuration defaults to the synthetic `exchange-demo`. `niemify setup` writes configuration without removing existing registrations.
2. Register a readable local `.xsd` with `niemify upload inventory /path/to/exchange.xsd`. NIEMify stores an absolute path rather than a copy; keep the entry file and its relative imports in place. Use `--schema inventory` for named conversion or verification, or `niemify switch inventory` to make `verify` use it without `--schema` in later invocations. The Lua API also exposes `list()` and `builtin()`.
3. Use `niemify update inventory /path/to/replacement.xsd` to replace the stored path without switching names. Duplicate uploads, updates to unknown names, attempts to replace the built-in, and invalid paths are refused. Registration checks file suitability, not the schema contents or dependency tree. If a file moves, restore it or update the registration; if a dependency is missing, restore it before retrying validation.
4. Configuration belongs to the local user. It lives in `config.json` under `NIEMIFY_HOME` when set, otherwise under `niemify/` in the user's XDG configuration directory or `$HOME/.config`. Mutations use a lock and replace the config file in place; commands do not rewrite source XSDs.

## Acceptance cases

| Case | Start and action | Observable result | Status |
|---|---|---|---|
| AC1 — Register and reuse | Isolated `NIEMIFY_HOME`; upload the included inventory entry XSD; use the named schema for conversion and verification | Both commands find the saved schema in separate invocations and resolve its sibling import from the original location. | Verified — baseline Ubuntu CI |
| AC2 — Switch and update | Fresh local config; register schema A, switch to it, then update the same name to schema B and validate against the default | The active name is unchanged after update; the default resolves B and rejects a message only valid with A. | Verified — baseline Ubuntu CI, Lua schema API |
| AC3 — Refuse unsafe replacement | With an existing registration and a config snapshot, attempt a duplicate upload, a built-in replacement, and an update to a missing path. Then update to a readable replacement. | Rejected requests exit nonzero and do not alter the stored registrations or active name. A valid update changes only the requested registration's path. | Implemented — unverified as a combined CLI recovery scenario |

## Status and evidence

The [schema registry](../../../niemify/schema.lua) owns local persistence; the [CLI](../../../bin/niemify) exposes the management commands. [Ubuntu GitHub Actions, 2026-11-20 UTC, `9f93b40064`](https://github.com/ObsaSiyo/niemify/actions/runs/44669729411) ran [schema tests](../../../tests/schema.lua) and the [CLI inventory workflow](../../../tests/run.sh). The switch/update evidence is at the Lua registry boundary, not a separate installed-CLI recovery run.
