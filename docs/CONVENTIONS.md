# Conventions

> Architecture: [ARCHITECTURE.md](ARCHITECTURE.md) - API: [API.md](API.md) - Contracts & specs: [SPEC.md](SPEC.md) - Errors & tooling: [DIAGNOSTICS.md](DIAGNOSTICS.md)

This document is the checklist for writing code that fits into AetherSystems.

## Philosophy

> Only build what solves a real pain point today.

- **No base classes to extend.** A module is a module: `require()` it and use it.
- **No auto-generated remotes.** The transport is two shared remotes addressed by event-name strings.
- **The loader's job is discovery, dependency resolution, and ordered initialization at boot - nothing more.**
- **Convention over configuration.** Discovery is folder-based; there is no central load list to maintain.
- **Fail loud, fail early** on the server; **skip + report** on the client.

## Adding a server system

1. Create a folder inside `ServerScriptService/AetherSystems/Systems/` (game features) or `Services/` (reusable services).
2. Drop a `ModuleScript` inside it - the **primary module**. It can be nested up to 3 folder levels deep; the innermost folder name becomes the default registry name.
3. Give the module a `Descriptor`:

```lua
local MySystem = {}

MySystem.Descriptor = {
    Name = "MySystem",             -- registry key (defaults to folder name)
    Dependencies = { "Network" },  -- registry names of other Services/Systems
}

function MySystem.Init(services)
    local Network = services.Network
end

return MySystem
```

4. Done. No central list to update.

## Module contract

### Descriptor

- `Descriptor.Name` - registry key. Defaults to the (innermost) folder name if absent. Must be a string; must be unique across `Services/` + `Systems/` (duplicates are a hard server error).
- `Descriptor.Dependencies` - array of registry names. Missing or circular dependencies are a **hard server error at boot**; on the client the affected systems are skipped and reported.
- A module without `Init` is registered but never initialized.
- Client modules may declare dependencies as a top-level `Dependencies = { ... }` table instead of `Descriptor.Dependencies` - the client loader accepts both (server accepts `Descriptor` only).

### Init(services)

- Called **exactly once**, in dependency order.
- Receives `services`, a table keyed by registry name containing every successfully initialized module so far (included: your dependencies).
- Access dependencies via `services.X` - no `WaitForChild`, no path traversal, no `require` in business logic.
- Don't `require` other systems directly; depend on them and take them from `services`.

```lua
function MySystem.Init(services)
    local Network = services.Network   -- NetworkServer
    local Motion  = services.Motion    -- TweenDriver
end
```

## Naming

| Thing | Convention | Example |
|---|---|---|
| Service folders | PascalCase, singular | `Network`, `Motion` |
| System folders | PascalCase, grouped by domain | `Interaction/Doors` |
| Primary module | same as folder name, or `<Name>Client`/`<Name>Server` | `NetworkServer`, `TweenDriver`, `MotionClient` |
| Registry name | `Descriptor.Name` (or folder name) | `"Network"`, `"Motion"`, `"Doors"` |
| Event names | `Domain.Action` camelCase | `"Combat.Hit"`, `"Motion.Tween"` |
| Tags | `Domain_Thing` snake_case | `Generic_Door` |

### Primary-module resolution

- **Server** (`Discovery`): the first `ModuleScript` found depth-first within 3 levels; the entry name is the innermost folder name.
- **Client** (`AetherClientLoader`): try `folderName`, then `folderName .. "Client"`, then `folderName .. "Server"`, then the first `ModuleScript` alphabetically. Extra modules in a folder (`Utils`, `Config`, ...) are **not** loaded by the loader - they exist only to be required by the primary module.

> The two loaders intentionally resolve primary modules differently: server discovery keys on folder structure, client discovery keys on naming. When a folder contains exactly one primary module, both produce the same result.

## Folder structure rules

- `Services/` - reusable, often-depended-on modules (Network, Motion, ...). May declare `Descriptor.Name` different from folder (e.g. `Motion` for folder `Motion/TweenDriver`).
- `Systems/` - game features that consume services. Nested folders are fine (the innermost folder's name is the entry name).
- Direct `ModuleScript` children of `Services/` or `Systems/` are also discovered (registered under their own name).
- Anything under `Core/` is internal to the loader - require `Core.AetherLoader` only.
- `AetherShared/` is shared, replicated storage - anything there is visible to clients. Keep server-only logic out of it (the exception is that `NetworkCore` lives there because both sides need it).
- `Config/` holds server configuration modules; `Events/` holds runtime `BindableEvent`s.
- Client equivalents mirror the server: `AetherClient/Services`, `AetherClient/Systems`, primary module naming per above.

## Error handling

- **`Logger:Fatal` throws** - use it only where execution should stop, and wrap the call site in `pcall` to recover. `Logger:Error` behaves like `Warn` (logs a warning and execution continues).
- Server dependency problems **error at boot** with system name + dependency name (see [DIAGNOSTICS.md](DIAGNOSTICS.md)).
- Use `pcall` at trust boundaries: handlers, middleware, `Init` calls, and remote-invoke handlers are all pcall-isolated by the framework.
- `assert` for programmer errors (invalid config, wrong argument types) with a `[Module.Function]` prefix.

## Code style

- Luau: use type annotations on function signatures and config tables (`type MoveConfig = { ... }`).
- One module per concern; keep modules small and focused (see the loader's `Discovery` / `Resolver` / `Loader` split).
- `task.*` API (`task.wait`, `task.delay`, `task.spawn`, `task.defer`) - no `wait()`/`delay()`/`spawn()`.
- `table.pack`/`table.unpack` with explicit bounds when forwarding varargs, so `nil` arguments survive (see `NetworkClient` queue and `packet.args`).
- Comments explain *why*, not *what*. Preserve the existing section banners (`-- === Public API ===` etc.).
- Deterministic ordering matters: folders and dependency queues are sorted where the order affects boot.

## Network conventions

- **Every message is addressed by an `eventName` string as the first argument** - there are exactly two remotes, never one per event.
- Event names: non-empty strings, max 64 chars (`NetworkCore.MAX_EVENT_NAME_LEN`), `Domain.Action` style.
- Server handlers receive `(player, ...)`; **validate the player**. Client handlers receive data only, never the player.
- Events = multi-handler (use `Network.On`). Invokes = single handler (use `Network.Handle`).
- Never fire to a nil/left player; `Fire` asserts the player.
- Rate-limit everything a client can spam; the limiter is middleware, so it covers events and invokes alike.
- Prefix events owned by the framework with the owning service: `Motion.Tween`, `Motion.Property`.

## Motion conventions

- Prefer `Move` for position/CFrame tweens (it handles Model vs BasePart, snapping, and replication); use `Property` for non-position properties; use `Local` only for server-invisible objects.
- One active tween per instance - check the `nil` return / handle `Cancel` rather than fighting the registry.
- If you `Wait = true`, prefer passing `Wait` over manual `task.wait(duration)` loops - `Cancel` unblocks it.

## Testing / dev tooling

- Dev/test scripts live in `ServerScriptService` at the top level and are **disabled by default** (`JanitorTest`, `NetworkInspector`, `TestInspector`, `LogHistory`). Follow that pattern for your own scratch scripts.
- Document every `CollectionService` tag you introduce in `ReplicatedStorage/AetherShared/TagList` (a `Configuration` named after the tag, e.g. `Generic_Door`).
