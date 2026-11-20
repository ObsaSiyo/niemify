# Install NIEMify from a checkout

## Outcome and scope

A developer on macOS or Linux can install the Lua CLI and library into a chosen LuaRocks tree and invoke them outside the checkout. This covers the documented local build, not registry publication, npm/Bun delivery, Windows, or installation of the optional NIEM evaluator.

## Beginning-to-end flow

1. Start with a checkout, Lua 5.4, LuaRocks, and Lua and Expat development headers for builds. Follow the [installation guide](../../../README.md#install). For basic XSD verification also put `xmllint` on `PATH`; Java and SCHEval are not needed for help, unvalidated conversion, or the [basic verification path](niem-conformance.md).
2. Run `luarocks --lua-version=5.4 make niemify-2.0.0-1.rockspec`. For an isolated installation specify `--tree` and load its LuaRocks environment so the tree's executables and modules can be found. The [rockspec](../../../niemify-2.0.0-1.rockspec) installs the CLI, Lua modules, and synthetic `exchange-demo` schema. Installation does not register a local schema or require `NIEMIFY_HOME` to exist.
3. From a different working directory, use `niemify --version` and `niemify help`, import `niemify` with Lua 5.4, or verify the checkout's built-in-demo sample by absolute path with `xmllint` available. If the build cannot find Lua headers, install the Lua 5.4 development package and rerun; if a custom tree is not visible, load its environment and retry without rebuilding.

## Acceptance cases

| Case | Start and action | Observable result | Status |
|---|---|---|---|
| AC1 — Install and run outside the checkout | Clean Linux checkout, Lua 5.4, documented packages, temporary rock tree; build the rock, load its environment, move to a different directory and verify the [exchange demo](../../../examples/exchange.xml) by absolute path | The installed executable runs and validates using the bundled schema without preexisting config. | Verified — baseline Ubuntu CI |
| AC2 — Use preinstalled dependencies offline | Network-denied Linux with compatible Lua modules already installed; build into a fresh tree with dependency resolution disabled and run the documented basic check with Java and SCHEval off `PATH` | The binary works, reports XSD passed and NDR not checked, and does not create config or download dependencies during validation. | Verified — Linux aarch64, installed rock |
| AC3 — Recover from missing headers on a new host | Fresh supported macOS setup without accessible Lua 5.4 headers; attempt the build, install the missing headers, rebuild and exercise both CLI and Lua import outside the checkout | The first attempt reports the missing prerequisites. The corrected build exposes `niemify` and `require('niemify')` from the chosen tree. | Implemented — unverified on fresh macOS |

## Status and evidence

[Ubuntu GitHub Actions, 2026-11-20 UTC, `9f93b40064`](https://github.com/ObsaSiyo/niemify/actions/runs/44669729411) ran the [build and outside-checkout smoke](../../../.github/workflows/test.yml). The [installed-rock acceptance](../../tasks/niem-conformance.md#L93) used network-denied Linux aarch64 with preinstalled distro modules. Neither run verifies dependency installation or recovery on a clean macOS machine, and neither implies the package was published.
