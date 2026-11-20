# NIEMify installation tasks

Source: [Install NIEMify from a checkout](../spec/features/install-niemify.md).

AC1 (Linux installation) and AC2 (offline Linux with preinstalled dependencies) have [recorded install evidence](../spec/features/install-niemify.md#status-and-evidence).

- [ ] **install-niemify-01 Verify fresh macOS install and header recovery**
  - Source: [AC3 — Recover from missing headers on a new host](../spec/features/install-niemify.md#acceptance-cases)
  - Depends on: none
  - Blocked: Needs a disposable macOS VM or fresh test host where Lua 5.4 headers can start absent and then be installed. This workstation already has the development installation; do not remove or hide its dependencies as a substitute for the fresh-host run.
  - Change: Verification only. Use a fresh checkout and a temporary rock tree; install missing headers only in the disposable environment. Do not modify the workstation or publish a package.
  - Done when: The initial build fails with the missing-header diagnostic; after supplying headers, the build succeeds and both the installed CLI and imported Lua module work outside the checkout without relying on the checkout's module search path.
  - Verify: On the disposable macOS host, run `luarocks --lua-version=5.4 --tree=<temp-tree> make niemify-2.0.0-1.rockspec` from the checkout before and after header setup. Load the tree's environment, change to an unrelated directory, run `niemify --version`, then use `lua5.4 -e` to require `niemify` and convert a small synthetic XML element. Record commands, versions, and outputs.
  - Supplemental smoke (not AC3): On 2026-11-20 UTC, macOS arm64 with Lua 5.4.9 and development headers already installed, `luarocks --lua-version=5.4 --lua-dir=/opt/homebrew/opt/lua@5.4 --tree=<temp-tree> make niemify-2.0.0-1.rockspec` passed. From outside the checkout, the installed CLI and Lua API worked; help variants matched, the XML/JSON round trip passed XSD and preserved SKU order, a bad SKU failed, and `verfiy` suggested `verify`. No configuration was created. Missing-header recovery was not exercised.
