# Releases

All notable changes to AetherSystems are documented here. Format follows the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style, and versions
match the boot banner printed by `AetherLoader`.

Announcement: [Open Source] AetherSystems - A Minimalist Module & Network Framework
([DevForum](https://devforum.roblox.com/t/open-source-aethersystems-a-minimalist-module-network-framework/4813570/1)).

## [V.1.1.0] - 2026-08-16

### Added

- **`AetherShared/Utils/RaycastUtil`** - a named cache of reusable `RaycastParams`
  objects (`Register` / `Update` / `Get` / `Remove` / `Exists`). `Get()` always
  returns the same instance and `Update()` mutates it in place, so pre-held
  references stay in sync. Use it for line-of-sight checks instead of building a
  new `RaycastParams` every frame.
- **`Systems/Combat/Turret`** - a new use-case system (CollectionService tag
  `"Turret"`) that tests the framework pieces working together. A model with a
  `Base` part and a `Head` part rotates its `Head` toward the nearest player
  within 60 studs that it has a clear line of sight to, using `RaycastUtil` for
  the LOS check, `Motion` for the rotation, `Janitor` for cleanup, and
  `Logger` for transitions.
- **`Test/RaycastUtilTest`** - a regression test proving `Get()` returns the
  same object every call, `Update()` mutates pre-held references, and native
  `workspace:Raycast` works directly with the returned params.

### Changed

- Version banner updated to `AetherSystems-Framework V.1.1.0`.
- Dev/test scripts (`JanitorTest`, `LogHistory`, `NetworkInspector`,
  `TestInspector`) moved into a dedicated `ServerScriptService/Test/` folder;
  they remain disabled by default.

### Documentation

- `docs/API.md` - added the `RaycastUtil` section (full member reference),
  documented the missing `Logger` history API (`GetHistory`, `GetCount`,
  `ClearHistory`, `GetEngineHistory`, `IsDebugEnabled`), and the
  `NetworkServer.Trace` pass-through.
- `docs/ARCHITECTURE.md`, `docs/CONVENTIONS.md`, `docs/DIAGNOSTICS.md` -
  documented the `Turret` use-case system and its tags/warnings, and updated the
  dev-script locations to `ServerScriptService/Test/`.
- `README.md` - added `RaycastUtil` to the "What's included" table, plus usage
  examples for `RaycastUtil` and the tracking turret.
- `docs/SPEC.md` - baseline bumped to `V.1.1.0`.

## [V.1.0.0] - 2026-08-15

Initial release of the AetherSystems framework:

- Module loader with dependency resolution (server: fail loud, fail early;
  client: skip + report).
- `Network` service - events and invokes over two shared remotes, with
  middleware and built-in rate limiting.
- `Motion` service - server-driven tweens (`Move`, `Property`, `Local`) that
  replicate smoothly to every client.
- Shared utilities: `Logger`, `Janitor`, `NetworkCore`.
- Example `Doors` system (`Generic_Door` tag) using `Motion`.
- Full documentation set (`docs/`) and the `sync/` mirror of the game code.
