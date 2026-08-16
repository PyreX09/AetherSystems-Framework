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
| System folders | PascalCase, grouped by domain | `Interaction/Doors`, `Combat/Turret` |
| Primary module | same as folder name, or `<Name>Client`/`<Name>Server` | `NetworkServer`, `TweenDriver`, `MotionClient` |
| Registry name | `Descriptor.Name` (or folder name) | `"Network"`, `"Motion"`, `"Doors"`, `"Turret"` |
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

```lua
-- ==== server side (any system's Init) ====
local Network = services.Network

-- events: multi-handler; every On returns its own disconnect fn
local disconnect = Network.On("Combat.Hit", function(player, data)
    -- player is ALWAYS first on the server - validate it
    if not player or not player.Parent then return end
end)
-- disconnect()  -- remove only this handler

Network.Fire(player, "Combat.Hit", data)     -- to one player
Network.FireAll("Announcement.Global", msg)  -- to everyone

-- invokes: ONE handler per event (re-registering warns + replaces)
Network.Handle("Inventory.Get", function(player, itemId)
    return makeItem(itemId)  -- single return value
end)

-- middleware: runs before dispatch, for events AND invokes
local remove = Network.Use(function(packet, next)
    if packet.eventName == "Blocked" then return end  -- drop
    next()                                            -- continue
end)

-- ==== client side ====
local Network = services.Network

local disconnect = Network.On("Combat.Hit", function(data)
    -- data only - NEVER the player
end)
Network.FireServer("Combat.Attack", data)
local item = Network.Invoke("Inventory.Get", itemId)  -- yields; nil on timeout/error
```

## Motion conventions

- Prefer `Move` for position/CFrame tweens (it handles Model vs BasePart, snapping, and replication); use `Property` for non-position properties; use `Local` only for server-invisible objects.
- One active tween per instance - check the `nil` return / handle `Cancel` rather than fighting the registry.
- If you `Wait = true`, prefer passing `Wait` over manual `task.wait(duration)` loops - `Cancel` unblocks it.

```lua
local Motion = services.Motion

-- CFrame/position tweens: plays on every client, server snaps when done
local handle = Motion.Move(door, {
    Goal     = CFrame.new(0, 10, 0),   -- CFrame or Vector3 (required)
    Duration = 0.8,                     -- seconds (required)
    Wait     = false,                   -- block until finished? (default false)
    Style    = Enum.EasingStyle.Bounce, -- optional, default Sine
})
handle.Cancel()  -- interrupt from outside; also unblocks Wait

-- non-position properties, with optional proximity filter (BaseParts, default 100 studs)
Motion.Property(part, {
    Property  = "Transparency",
    Goal      = 1,
    Duration  = 0.5,
    Proximity = 150,   -- only players within 150 studs see it
})

-- server-only tween (invisible to clients); returns the actual Tween
local tween = Motion.Local(part, { Property = "Transparency", Goal = 0, Duration = 1 })

-- cancel anything on an instance (registry + playback for Local)
Motion.Cancel(part)
```

## RaycastUtil conventions

`RaycastUtil` is a named cache of `RaycastParams` - register a set of params once and reuse the same object everywhere. It does **not** wrap `workspace:Raycast()`; you call the native API with the object `Get()` returns.

- **Register once, then reuse.** Call `Register(name, config)` in your system's `Init` (or lazily guarded by `Exists`). `Get(name)` returns the *same* instance on every call - never re-create it per frame.
- **`Update()` mutates in place.** Pre-held references stay in sync, so keep one reference and `Update` it before each use.
- **No yields between `Update` and `Raycast`.** The whole point is that the params object is never re-created, so there is no reason to yield between mutating and casting.
- Only these `RaycastParams` properties are recognized: `FilterType`, `FilterDescendantsInstances`, `IgnoreWater`, `CollisionGroup`, `RespectCanCollide`, `BruteForceAllSlow`. Anything else throws (`Logger:Fatal`) at `Register`/`Update` time - it catches typos before they silently break a raycast.
- Name params `Domain.Purpose` (e.g. `"Turret.LOS"`) to avoid collisions with other systems.

```lua
local RaycastUtil = require(game:GetService("ReplicatedStorage").AetherShared.Utils.RaycastUtil)

-- in Init: register once
if not RaycastUtil.Exists("Enemy.LOS") then
    RaycastUtil.Register("Enemy.LOS", {
        FilterType = Enum.RaycastFilterType.Exclude,
        FilterDescendantsInstances = {},
    })
end

-- per scan: Update + immediate Raycast, no yields between
RaycastUtil.Update("Enemy.LOS", { FilterDescendantsInstances = { enemyModel, character } })
local hit = workspace:Raycast(origin, direction, RaycastUtil.Get("Enemy.LOS"))
```

## Logger conventions

`Logger` is the single way to emit output - fixed-width `[time][level][category]` lines. Every system logs through it with its own category (usually the registry name).

- **Pick a category and stick to it.** Use the registry name (`"Turret"`, `"Doors"`) or a subsystem name (`"Resolver"`, `"RateLimit"`) - it's the column everyone reads to find your lines.
- **Levels are ordered:** `Debug` (gated, default off) < `Info` < `Warn` < `Error` (warns, does **not** throw) < `Fatal` (**throws**). Use `Error` where you want visibility without halting; use `Fatal` only where execution must stop, wrapped in `pcall` if you need to recover.
- **Multiple values join with ` | `** - pass them as separate args, don't pre-format into one string. Tables print as `[table]`, functions as `[function]`, `nil` as `nil`.
- **`Debug` is invisible by default.** Gate noisy per-frame output behind `Logger:Debug` and flip `Logger:SetDebug(true)` during development.
- **Profile with `Begin`/`End` or `TimeAsync`** instead of hand-rolling `os.clock` prints.

```lua
local Logger = require(game:GetService("ReplicatedStorage").AetherShared.Utils.Logger)

local TAG = "Shop"

Logger:Info(TAG, "Item purchased", itemId, player.Name)   -- multiple args join with |
Logger:Warn(TAG, "Item not found", itemId)
Logger:Error(TAG, "Purchase failed", reason)              -- warns, continues
Logger:Debug(TAG, "detailed state", state)                -- hidden unless SetDebug(true)
Logger:SetDebug(true)                                     -- enable Debug lines

-- Fatal throws - only where execution must stop
if not item then
    Logger:Fatal(TAG, "Item table is nil")
end

-- profiling
Logger:Begin("SellFlow")
-- ...work...
Logger:End("SellFlow")                       -- [PROFILE] SellFlow | (0.0042 sec)
Logger:TimeAsync("Shop", function() ... end) -- runs in a task.spawn, logs duration

-- history (used by the LogHistory dev tool)
local recent = Logger:GetHistory({ level = "WARN", category = "shop", limit = 20 })
```

## Janitor conventions

`Janitor` is the cleanup tracker - hand it connections and instances and it disposes of them when you're done, instead of scattering `Disconnect`/`Destroy` calls.

- **Create one per tracked object**, not per system. A turret, a door, a UI panel - each gets its own janitor (see the `Turret` use case: one janitor per model, destroyed when the model leaves).
- **Method inference:** `RBXScriptConnection` -> `Disconnect`; `Instance` -> `Destroy`; table with a `Destroy` method -> `Destroy`; functions are called directly. Anything else needs an explicit method name or it asserts.
- **Use the index parameter for replaceable slots** - re-`Add`ing the same index cleans the old occupant first (e.g. swap a highlight connection without leaking the old one).
- **`Cleanup` keeps the janitor usable; `Destroy` locks it forever.** Prefer `Destroy` when the owning object is going away.

```lua
local Janitor = require(game:GetService("ReplicatedStorage").AetherShared.Utils.Janitor)

local janitor = Janitor.new()

janitor:Add(connection)                  -- RBXScriptConnection -> infers Disconnect()
janitor:Add(part)                        -- Instance -> infers Destroy()
janitor:Add(tbl, "Stop")                 -- explicit method name
janitor:Add(function() ... end)          -- called directly

-- indexed: replacing "highlight" cleans the old one first
janitor:Add(part, "Destroy", "highlight")
janitor:Add(part2, "Destroy", "highlight")  -- part is cleaned automatically

janitor:Remove("highlight")              -- clean + drop one indexed item
janitor:Cleanup()                        -- clean everything; janitor stays usable
janitor:Destroy()                        -- Cleanup() + janitor locked forever
```

## Use case: the Turret system (`Systems/Combat/Turret`)

`Turret` is a **use case / test** of the framework pieces working together - a CollectionService-tagged model driven by `RaycastUtil` + `Motion` + `Janitor` + `Logger`. Read it to see each convention above in action, not as production code to copy wholesale.

**Setup in Studio:** a `Model` tagged `"Turret"` containing a `Base` part and a `Head` `BasePart`. Tag it at runtime or in Studio:

```lua
CollectionService:AddTag(turretModel, "Turret")
```

**How it works (read `Turret.luau` for the full implementation):**

1. **Descriptor** - `Name = "Turret"`, `Dependencies = { "Motion" }`. `Init` takes `Motion` from `services` (with a `Loader.Get("Motion")` fallback) and `Logger:Fatal`s if it's missing.
2. **LOS params** - registers `"Turret.LOS"` once (`RaycastUtil.Register`), then per scan does `Update` (excluding the turret + candidate character) followed by an immediate `workspace:Raycast`.
3. **Targeting** - scans players every `0.3s` (`SCAN_INTERVAL`), picks the nearest `HumanoidRootPart` within `60` studs (`RANGE`) with a clear ray, and rotates the `Head` with `Motion.Move` using `CFrame.lookAt` (y-axis locked).
4. **Cleanup** - each turret gets a `Janitor`; a cooperative `scanning` flag stops the loop and an `AncestryChanged` connection destroys the janitor when the model leaves the game.
5. **Logging** - `Logger:Info` on target acquired/lost transitions and a boot summary (`initialized, tracking N turret(s)`).

```lua
-- the shape to copy for your own tagged, tracked systems:
function Module.Init(services)
    local Motion = services.Motion  -- or Loader.Get("Motion")
    if not Motion then
        Logger:Fatal("Turret", "Motion system not available")
    end
    -- register params, connect GetTagged/GetInstanceAddedSignal, return a handle
end
```

## Testing / dev tooling

- Dev/test scripts live in `ServerScriptService/Test/` and are **disabled by default** (`JanitorTest`, `LogHistory`, `NetworkInspector`, `TestInspector`, `RaycastUtilTest`). Follow that pattern for your own scratch scripts.
- Document every `CollectionService` tag you introduce in `ReplicatedStorage/AetherShared/TagList` (a `Configuration` named after the tag, e.g. `Generic_Door`, `Turret`).
