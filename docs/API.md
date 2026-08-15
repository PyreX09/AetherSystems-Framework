# API Reference

> Architecture: [ARCHITECTURE.md](ARCHITECTURE.md) - Conventions: [CONVENTIONS.md](CONVENTIONS.md) - Contracts & specs: [SPEC.md](SPEC.md) - Errors & tooling: [DIAGNOSTICS.md](DIAGNOSTICS.md)

## Contents

- [AetherLoader (server)](#aetherloader-server)
- [NetworkServer (server, registered as "Network")](#networkserver-server)
- [NetworkClient (client, registered as "Network")](#networkclient-client)
- [TweenDriver (server, registered as "Motion")](#tweendriver-server)
- [MotionClient (client)](#motionclient-client)
- [Logger (shared)](#logger-shared)
- [Janitor (shared)](#janitor-shared)
- [NetworkCore (shared)](#networkcore-shared)
- [NetworkConfig (server)](#networkconfig-server)

---

## AetherLoader (server)

`require(ServerScriptService.AetherSystems.Core.AetherLoader)` - the only public entry point into the server framework. Requiring it starts boot (banner + pipeline).

| Member | Returns | Description |
|---|---|---|
| `AetherLoader.Get(name: string)` | module | Returns the initialized module registered under `name`. Blocks until boot finishes; throws if boot failed. Returns `nil` (with a `Logger:Error` warning listing the available names) if `name` isn't registered - it does not throw. |
| `AetherLoader.List()` | `{ string }` | Sorted list of registered system names. Blocks until boot finishes; throws if boot failed. |
| `AetherLoader.IsReady()` | `boolean` | Whether boot completed successfully. |

```lua
local Loader = require(game:GetService("ServerScriptService").AetherSystems.Core.AetherLoader)

local Network = Loader.Get("Network")
local Motion  = Loader.Get("Motion")
print(Loader.List())   -- { "Doors", "Motion", "Network" }
```

> Inside `Init(services)`, prefer `services.Network` over `Loader.Get("Network")` - it's already there and doesn't require the loader.

---

## NetworkServer (server)

Registered as **`"Network"`**. Get it from `services.Network` in `Init` (or `Loader.Get("Network")`).

### Events (fire-and-forget)

```lua
-- register a handler (multi-handler: several handlers per event, each removable)
local disconnect = Network.On("Combat.Hit", function(player, data)
    -- player is ALWAYS the first argument on the server
end)
disconnect() -- remove only this handler

-- fire
Network.Fire(player, "Combat.Hit", data)   -- to one player
Network.FireAll("Combat.Hit", data)        -- to every player
```

- Server handlers receive `(player, ...)` - validate the player.
- Every handler runs under its own `pcall`; one crashing handler doesn't affect the others.
- Registering the same event multiple times is fine; each `On` returns its own disconnect function.
- Firing an event with no handler logs a warning.

### Invokes (request/response)

```lua
-- register (single handler per event; re-registering warns and replaces)
Network.Handle("Inventory.Get", function(player, itemId)
    return makeItem(itemId)
end)

-- server-to-client invoke isn't in the public API; invokes are client->server.
```

- Invokes support **one** handler per name - a `RemoteFunction` must return a single result.
- If the handler throws, the client receives `nil` and the server logs a warning (pcall-isolated).

### Middleware

```lua
local remove = Network.Use(function(packet, next)
    if packet.eventName == "Blocked" then return end  -- drop
    next()                                            -- continue the chain
end)
```

- Middleware runs **before** dispatch, for both events and invokes.
- `packet` is `{ player, eventName, args = table.pack(...) }`.
- Calling `next()` twice warns and is ignored. A throwing middleware logs `MiddlewareError` and stops the chain (the packet is dropped; an invoke returns `nil`).
- The rate limiter is installed as middleware in `Init`.
- `Use` returns a function that removes that middleware.

### Validation

- `Fire`/`FireAll` validate the player (Fire) and the event name (`ValidateEventName`) before sending.
- `eventName` must be a non-empty string of at most **64** characters (see [SPEC.md](SPEC.md#42-event-names)); anything else is rejected before dispatch.

---

## NetworkClient (client)

Registered as **`"Network"`**. Get it from `services.Network` in `Init`.

```lua
local Network = services.Network

-- handlers receive data only, NEVER the player
local disconnect = Network.On("Combat.Hit", function(data) end)

Network.FireServer("Combat.Attack", data)

local result = Network.Invoke("Inventory.Get", itemId)   -- yields until server responds
```

| Member | Description |
|---|---|
| `Network.On(eventName, handler)` | Register a multi-handler event listener; returns a disconnect function. |
| `Network.FireServer(eventName, ...)` | Send a fire-and-forget event to the server. |
| `Network.Invoke(eventName, ...)` | Call the server and wait for the return value. **10-second timeout** - on timeout the call returns `nil` and logs `TIMEOUT`; on server handler error it returns `nil` and logs `SERVER_ERROR`. |
| `Network.IsReady()` | Whether the client has finished `Init` (and flushed its queue). |

- `Invoke` yields the calling thread; calling it from a **non-yieldable context** (e.g. a `BindableFunction.OnInvoke` callback) throws with an explanatory message - wrap in `task.spawn` instead.
- Packets arriving before `Init` completes are queued and flushed (on a `task.defer`) once ready.

---

## TweenDriver (server)

Registered as **`"Motion"`**, depends on `Network`. Get it from `services.Motion` in `Init`.

### `Motion.Move(instance, config)` -> `{ Cancel } | nil`

Tween a `Model` (needs `PrimaryPart`) or `BasePart` to a CFrame. Fired to all clients; the server snaps the instance to the goal when done (authority).

```lua
local handle = Motion.Move(door, {
    Goal      = CFrame.new(0, 10, 0),        -- CFrame or Vector3 (required)
    Duration  = 0.8,                          -- seconds (required)
    Wait      = true,                         -- block until finished (default false)
    Style     = Enum.EasingStyle.Bounce,      -- optional, default Sine
    Direction = Enum.EasingDirection.Out,     -- optional, default InOut
    Relative  = false,                        -- Vector3 goal: offset from current CFrame
})
handle.Cancel()                               -- interrupt from outside; also unblocks Wait
```

- Returns `nil` (and warns) if a tween is already active on that instance - see [MotionRegistry](#one-active-tween-per-instance).
- `Goal` as a `Vector3` becomes a position tween that preserves the instance's current orientation (`Relative = true` adds the offset instead).

### `Motion.MoveBounce(instance, goal, duration, wait?)` / `Motion.MoveLinear(...)`

Convenience wrappers with Bounce/Out and Linear/InOut easing presets.

### `Motion.Property(instance, config)` -> `{ Cancel } | nil`

Tween any tweenable property; replicated to clients.

```lua
Motion.Property(part, {
    Property  = "Transparency",   -- property name (required)
    Goal      = 1,                -- target value (required)
    Duration  = 0.5,              -- seconds (required)
    Wait      = false,
    Style     = Enum.EasingStyle.Linear,
    Direction = Enum.EasingDirection.In,
    Proximity = 150,              -- BaseParts only: only players within N studs get it
})
```

- `Proximity` (default **100** studs) restricts the fire to players whose `HumanoidRootPart` is within range; omit it to use the default. For `BasePart` targets the part's own position is used; for `Light`/`Attachment`/`Sound` the parent part's position is used. Only when no position can be resolved does it fire to everyone (`FireAll`).

### `Motion.Local(instance, config)` -> `Tween`

Play a tween **only on the server** - no client replication. Same config as `Property` minus `Proximity`. The returned `Tween` is the actual `TweenService` tween; `Motion.Cancel(instance)` will cancel it mid-playback (unlike `Move`/`Property`, whose cancel only clears the registry).

### `Motion.Cancel(instance)` -> `boolean`

Force-clears any in-progress tween for the instance and unblocks any thread parked in a `Wait = true` call.

### One active tween per instance

`MotionRegistry` guarantees a single active tween per instance (token-based). A second `Move`/`Property`/`Local` on a busy instance returns `nil`, warns, and yields one frame so a tight retry loop can't starve the scheduler. `MotionRegistry.IsActive(instance, token)` is the single source of truth used by `Wait = true` loops.

---

## MotionClient (client)

Not called directly - auto-started by `AetherClientLoader` (depends on `Network`). Listens for `Motion.Tween` and `Motion.Property` and plays them with `TweenService`.

- CFrame tweens use a `CFrameValue` proxy (TweenService can't tween a `Model`'s CFrame directly) and a per-tween `Janitor` that cleans up on completion or when the instance is destroyed.
- Tweens arriving before `MotionClient.Ready` are queued and flushed in `Init`.

---

## Logger (shared)

`require(ReplicatedStorage.AetherShared.Utils.Logger)` - fixed-width column output:

```
[14:02:33    ][INFO  ][      Network       ] Ready
[14:02:33    ][WARN  ][     RateLimit      ] Blocked | player: Player1 | event: BuyItem | 31/30 per 1s
```

| Member | Description |
|---|---|
| `Logger:Info(category, ...)` | `print` with `[time][INFO][category] message`. |
| `Logger:Warn(category, ...)` | `warn` with the same layout. |
| `Logger:Error(category, ...)` | `warn` output with the same layout; does **not** throw. |
| `Logger:Fatal(category, ...)` | **Throws.** Calls `error()` internally and halts the calling thread - use only where execution must stop. |
| `Logger:Debug(category, ...)` | Same layout, gated by `Logger.DebugEnabled` (default `false`). |
| `Logger:SetDebug(enabled)` | Set debug output on/off (pass `true` or `false`). |
| `Logger:Banner(title)` | Prints a boxed banner (used for the version banner). |
| `Logger:Begin(name)` / `Logger:End(name)` | Time a named section; `End` logs `[PROFILE] name | (x.xxxx sec)`. |
| `Logger:TimeAsync(category, fn)` | Runs `fn` in a `task.spawn`, logs `done (x.xxxx sec)` or `failed (x.xxxx sec): err`. |

- Column widths: time 12, level 6, category 20. Tables print as `[table]`, functions as `[function]`, `nil` as `nil`.

---

## Janitor (shared)

`require(ReplicatedStorage.AetherShared.Utils.Janitor)` - cleanup tracker.

```lua
local janitor = Janitor.new()

janitor:Add(connection)                  -- RBXScriptConnection -> infers Disconnect()
janitor:Add(instance)                    -- Instance -> infers Destroy()
janitor:Add(tbl, "Stop")                 -- explicit method name
janitor:Add(fn)                          -- called directly
janitor:Add(part, "Destroy", "part")     -- indexed: replacing "part" cleans the old one first

janitor:Remove("part")                   -- clean + drop one indexed item
janitor:Cleanup()                        -- clean everything; janitor stays usable
janitor:Destroy()                        -- Cleanup() + janitor locked forever
```

Method inference order: `RBXScriptConnection` -> `Disconnect`; `Instance` -> `Destroy`; table with a `Destroy` method -> `Destroy`; functions are called directly. Anything else without an explicit method name asserts.

---

## NetworkCore (shared)

`require(ReplicatedStorage.AetherShared.Utils.NetworkCore)` - transport core. Usually you interact with it through `NetworkServer`/`NetworkClient`, but it's public for advanced/debug use.

| Member | Description |
|---|---|
| `NetworkCore.Remote` / `NetworkCore.Function` | The `RemoteEvent` / `RemoteFunction` instances. |
| `NetworkCore.ValidateEventName(name, context)` | Throws if not a non-empty string of at most 64 chars (see [SPEC.md](SPEC.md#42-event-names)). |
| `NetworkCore.NewRegistry()` | Returns `(Register, Dispatch)` - multi-handler registry with per-handler disconnect and pcall isolation. |
| `NetworkCore.NewInvokeRegistry()` | Returns `(RegisterHandler, DispatchInvoke)` - single-handler invoke registry; re-registering warns and replaces. |
| `NetworkCore.Debug` | Print `[Aether.Network]` send/receive lines when `true`. Per-VM flag (server and client are independent). |
| `NetworkCore.Trace(data)` | Record a trace entry (see [DIAGNOSTICS.md](DIAGNOSTICS.md#network-trace)). No-op unless `TraceEnabled`. |
| `NetworkCore.TraceEnabled` | Defaults to `RunService:IsStudio()` - tracing is Studio-only unless you flip this. |
| `NetworkCore.GetTrace()` | Copy of recent trace entries (ring buffer, 500 max), sorted by id. |
| `NetworkCore.ClearTrace()` | Empties the trace buffer. |
| `NetworkCore.MAX_EVENT_NAME_LEN` | `64`. |

---

## NetworkConfig (server)

`require(ServerScriptService.AetherSystems.Config.NetworkConfig)` - consumed by `RateLimit.Create`. See [SPEC.md - Configuration](SPEC.md#6-configuration-schema).

```lua
NetworkConfig.RateLimit = {
    Default = { limit = 30, window = 1 },  -- 30 calls/sec per player per event
    Overrides = {
        -- ["BuyItem"] = { limit = 5, window = 10 },
    },
}
```

- Per-event rules: `Overrides[eventName]` wins, else `Default`.
- `limit <= 0` disables the event entirely (every call dropped + `RateLimit.Blocked` fired).
- `window` is the fixed-window duration in seconds (`os.clock`).
