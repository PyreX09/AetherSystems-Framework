# Baseline & Specification

> This is the **baseline** for AetherSystems-Framework **V.1.0.0** - a precise description of the contracts as they exist in the code today. Use it as the reference point for changes: any deviation from these rules is a breaking change unless the spec is updated too.
>
> Architecture: [ARCHITECTURE.md](ARCHITECTURE.md) - API: [API.md](API.md) - Conventions: [CONVENTIONS.md](CONVENTIONS.md) - Errors & tooling: [DIAGNOSTICS.md](DIAGNOSTICS.md)

## 1. Version

- Banner: `AetherSystems-Framework V.1.0.0` (printed by `AetherLoader` on boot).
- Status: in active development; this spec describes the code as it exists now.

## 2. Module descriptor

A system is any `ModuleScript` discovered under `Services/` or `Systems/` that returns a table. Its optional `Descriptor`:

```lua
MySystem.Descriptor = {
    Name         = "MySystem",             -- string, registry key (default: folder name)
    Dependencies = { "Network" },          -- array of registry names
}
```

Semantics:

- `Descriptor.Name` must be a string when present; otherwise the entry name is the innermost folder name (server discovery) or the folder name (client discovery).
- Names must be unique across `Services/` and `Systems/` combined. Duplicates:
  - **Server:** hard error at boot.
  - **Client:** warning; the later duplicate is ignored.
- `Descriptor.Dependencies` entries must be names present in the registry:
  - **Server:** a missing dependency is a hard error at boot.
  - **Client:** the system is skipped; the skip propagates transitively to its dependents.
- A module without `Init` is registered but never initialized.

## 3. Dependency resolution

Algorithm: **Kahn's algorithm** (topological sort), deterministic:

- The seed queue (nodes with in-degree 0) is sorted alphabetically.
- After each node is processed, newly freed nodes are appended sorted.
- Server resolver re-sorts the whole queue after each step; client resolver sorts only the newly freed batch (documented in-code as "topology deterministic, not lexicographically smallest").

Rules (server, hard errors):

| Condition | Server behavior | Client behavior |
|---|---|---|
| Missing dependency | `error` naming system + dependency | skip + transitive skip |
| Cycle | `error` listing remaining (in-degree > 0) nodes | skip; reported as circular in boot summary |
| Duplicate name | `error` | warn + ignore later |
| `require` failure | `error` | skip with reason |
| `Init` failure | warn + skip (never registered) | warn + skip |

Order guarantee: for every system `A` depending on `B`, `B.Init` completes before `A.Init`.

## 4. Network protocol

### 4.1 Transport

Two remotes, both under `ReplicatedStorage.AetherShared.Event.Network`:

| Instance | Class | Purpose |
|---|---|---|
| `Event` | `RemoteEvent` | fire-and-forget events |
| `Function` | `RemoteFunction` | invokes |

Every message carries the **event name as the first argument**, followed by the payload.

### 4.2 Event names

- Must be a non-empty `string`, length <= 64 (`NetworkCore.MAX_EVENT_NAME_LEN`).
- `NetworkCore.ValidateEventName(name, context)` throws otherwise; it is called on every send (`Fire`, `FireAll`, `FireServer`, `Invoke`) and on every registry registration.
- Inbound packets with invalid event names are **dropped** (server: warns; invoke path: returns `nil`; client: warns).
- Convention: `Domain.Action` (e.g. `Combat.Hit`, `Motion.Tween`).

### 4.3 Wire format

- Event: `RemoteEvent:FireClient(player, eventName, ...)` / `FireAllClients(eventName, ...)` / `FireServer(eventName, ...)`.
- Invoke: `RemoteFunction:InvokeServer(eventName, ...)`; server returns the handler's (multiple) return values; `nil` on handler error or middleware block.
- Server-side packet struct (before middleware): `{ player, eventName, args = table.pack(...) }`.
- Client queue entry (pre-`Init`): `{ eventName, args = table.pack(...) }` - `table.pack` preserves `nil` arguments across `unpack`.

### 4.4 Handler semantics

- **Events:** multi-handler. `Network.On(eventName, handler)` -> disconnect fn removing only that handler. Dispatch iterates a snapshot of the list and pcall-isolates each handler; a crashing handler logs and continues. No handler -> `Warn("[Aether.Network] No handler for event:X")`.
- **Invokes:** single handler. `Network.Handle(eventName, handler)` -> disconnect fn. Re-registering warns and **replaces** (intentional - a RemoteFunction must return one value). Handler errors are pcall-isolated: warn + return `nil`.

### 4.5 Middleware

- `Network.Use(fn)` appends `fn(packet, next)` to the chain and returns a removal function.
- `next()` must be called exactly once to continue; a second call warns and is ignored.
- A middleware that throws logs `MiddlewareError | event=... playerId=... err=...` and **stops the chain** (packet dropped; invoke returns `nil` via `onFailure`).
- Middleware runs for events and invokes alike, before dispatch.

### 4.6 Rate limiting

Implemented as middleware (`RateLimit.Create(config)`), per **player and eventName**, fixed window (using `os.clock`):

- Rule resolution: `config.Overrides[eventName]` -> `config.Default`. No rule -> warn + pass through.
- `limit <= 0` -> event disabled; every call dropped + blocked event fired.
- Window reset: when `now - bucket.start > rule.window`, the bucket resets.
- On exceed: call dropped + `BindableEvent "RateLimit.Blocked"` fired with `{ player, eventName, limit, window }`. The event lives at `ServerScriptService.AetherSystems.Events.RateLimit.Blocked` and is **created lazily** on first block.
- Buckets for a player are removed on `Players.PlayerRemoving` (memory hygiene).

### 4.7 Client transport details

- **Pre-`Init` queue:** packets arriving before `NetworkClient.Init` are queued and flushed via `task.defer` once ready.
- **`Invoke` timeout:** 10 s (`task.delay`). Results resume the waiting thread as `(data, nil)`, `(nil, "TIMEOUT")`, or `(nil, "SERVER_ERROR")`.
- **Yieldability:** `Invoke` throws if called from a non-yieldable context (e.g. `BindableFunction.OnInvoke`).

## 5. Motion protocol

Two server->client event names on the Network transport:

| Event | Payload (after eventName) |
|---|---|
| `Motion.Tween` | `(instance, goalCFrame, duration, easingData)` |
| `Motion.Property` | `(instance, property, goal, duration, easingData)` |

- `easingData = { Style, Direction }` - enums sent as EnumItems.
- **Move:** CFrame/Vector3 goal; Vector3 becomes a position-preserving-orientation CFrame (`Relative = true` adds offset). Fired to all clients. Server authority: on completion, `MotionRegistry`'s `task.delay` callback snaps the instance (`PivotTo` for Models, `CFrame` for BaseParts).
- **Property:** proximity-limited for `BasePart` targets - only players within `Proximity` studs (default 100) of the part get `Fire(player, ...)`. For non-BaseParts (`Light`, `Attachment`, `Sound`) the parent part's position is used; no resolvable position -> `FireAll`.
- **Local:** server-only `TweenService` tween; tracked in `_localTweens` so `Cancel` can halt actual playback.
- **One-tween-per-instance:** `MotionRegistry.Start` returns a token or `false`; `IsActive(instance, token)`; `Cancel(instance)`. Second concurrent tween -> `nil` + warn + one-frame yield.
- **`Wait = true`:** the calling thread loops on `MotionRegistry.IsActive`; `Cancel` clears the registry (and the actual tween for `Local`), unblocking it.

## 6. Configuration schema

`ServerScriptService.AetherSystems.Config.NetworkConfig`:

```lua
NetworkConfig.RateLimit = {
    Default   = { limit = 30, window = 1 },                     -- 30 calls/sec per player per event
    Overrides = { ["EventName"] = { limit = n, window = n } },  -- optional per-event rules
}
```

- Baselines as shipped: `Default = { limit = 30, window = 1 }`, no overrides.

## 7. Tracing (debug)

- `NetworkCore.TraceEnabled` defaults to `RunService:IsStudio()` - tracing costs nothing in production.
- `Trace(data)` stores lightweight metadata only (`Direction`, `Event`, `Target`, `Time`, `Id`, optional `Meta`) in a 500-entry ring buffer - never args/instances (memory + sensitive data).
- `Direction` values in use: `SEND`, `RECV`, `INVOKE`, `FLUSH`, `TEST`.
- `GetTrace()` returns a copy sorted by `Id`; `ClearTrace()` empties it.
- `NetworkCore.Debug` (per-VM flag) additionally prints `[Aether.Network] <DIR> <event> <target>` lines.

## 8. Logger contract

- Format: `[HH:mm:ss][LEVEL][      Category] message`, columns: time 12 / level 6 / category 20 (centered, truncated). Multiple args joined with ` | `; tables -> `[table]`, functions -> `[function]`, `nil` -> `nil`.
- Levels: `Debug` (gated by `DebugEnabled`, default off) < `Info` < `Warn` < `Error` (warns, does not throw) < `Fatal` (**throws**).
- `Begin`/`End` profile a named section; `TimeAsync` runs a function in a task and logs duration.

## 9. Compatibility notes

- Client systems may declare `Dependencies` either top-level or inside `Descriptor`; server systems must use `Descriptor.Dependencies`.
- The server `Loader` accepts `registry[name] = { Module = mod }` (current) and `registry[name] = mod` (backcompat).
