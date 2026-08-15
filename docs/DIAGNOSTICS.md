# Diagnostics & Errors

> Architecture: [ARCHITECTURE.md](ARCHITECTURE.md) - API: [API.md](API.md) - Conventions: [CONVENTIONS.md](CONVENTIONS.md) - Spec: [SPEC.md](SPEC.md)

## Error philosophy

- **Server:** fail loud, fail early. Dependency problems halt boot and the error names the exact system and dependency involved.
- **Client:** skip + report. Broken or circular systems are excluded and listed in the boot summary so the game still runs.

## Server boot errors

All boot-time errors are raised through `Logger` (`Resolver`, `Loader`, `SystemManager`) and name the exact system and dependency involved.

### Missing dependency

Produced by `Resolver.Resolve` when `Descriptor.Dependencies` names a system that isn't in the registry:

```text
[FATAL][Resolver] Missing dependency | Combat | -> | Network
```

### Dependency cycle

The resolver reports the remaining (in-degree > 0) nodes in one line:

```text
[FATAL][Resolver] Dependency cycle detected | A, B
```

### Duplicate system name

```text
[FATAL][Resolver] Duplicate system name detected | Network | (from folder | Network2)
```

### Failed require / failed Init

```text
[FATAL][Resolver] Failed to require system | Combat | attempt to index nil with 'Foo'
[WARN][Loader] Failed to initialize Combat: <error>
```

- A failed `Init` is **warned** and the system is skipped - it never enters the registry.
- A failed boot stores the error in `AetherLoader`; subsequent `Get`/`List` calls throw with `[AetherLoader] Boot failed, cannot Get('X'): <bootError>`.
- `SystemManager.Get` on an unknown name logs via `Logger:Error` (`[SystemManager] System not found: X | Available: A, B, C`) and returns `nil` - it does not throw.
- Missing loader-internal modules are logged via `Logger:Error` (e.g. `Module missing:Discovery`); `Logger:Error` warns and execution continues.

## Client boot summary

After `AetherClientLoader` finishes, it logs either:

```text
[AetherClientLoader] Boot complete. N system(s) initialized
```

or, when there were problems:

```text
[AetherClient]        circular dependency — NOT initialized: A, B
[AetherClient]        missing/invalid dependencies — NOT initialized: C
[AetherClientLoader]  Boot complete with N issue(s). See warnings above.
```

Each skipped system also logs a `[AetherClientLoader] Skipping X — dependency 'Y' is unavailable (...) / not found in registry` warning during validation.

## Logger:Fatal is fatal

`Logger:Fatal(category, ...)` stores the entry and calls `error()` - it **throws** and halts the calling thread. It is used for fatal conditions inside the framework (e.g. resolver failures in `Resolver`). `Logger:Error` does **not** throw - it logs a warning via `warn` and execution continues. Use `Fatal` only where execution must stop; wrap the call site in `pcall` if you need to recover.

## Network trace

`NetworkCore` keeps a ring buffer (500 entries) of recent network activity - metadata only (direction, event, target, time, id), never payloads.

- Enabled by default **only in Studio** (`TraceEnabled = RunService:IsStudio()`); set `NetworkCore.TraceEnabled = true` manually to force it.
- `NetworkCore.GetTrace()` / `ClearTrace()` read/reset the buffer.
- `NetworkCore.Debug = true` prints live lines: `[Aether.Network] SEND DoorOpen Player1`.

### Dev scripts (all in `ServerScriptService`, disabled by default)

| Script | What it does |
|---|---|
| `Diagnostics` (in `Core/AetherLoader/`) | Requires `Discovery` + `Resolver`, logs discovered entries, resolved order, and registry keys. Useful for inspecting the dependency graph without booting the game. |
| `NetworkInspector` | Every 5 s prints the trace buffer (`Direction | Event | Target` + `Meta`). |
| `TestInspector` | Forces `TraceEnabled = true`, records a `TEST` entry, then prints it. |
| `JanitorTest` | Manual smoke test of `Janitor` (12 checks: method inference, indexed add/replace, remove, cleanup reuse, destroy lock). Prints `[JanitorTest] N/12 passed`. |
| `LogHistory` | Prints every entry from `Logger:GetHistory()` (id, timestamp, time, level, category, message). |

Enable a disabled script (set its `Enabled = true` / uncheck "Disabled") to run it in a playtest, or paste its body into the command bar.

## Rate limit diagnostics

- Every blocked call logs: `Blocked | player: <Name> | event: <Event> | <count>/<limit> per <window>s`.
- `limit <= 0` logs `Blocked by config | event=... playerId=...`.
- The same data is also fired on `AetherSystems.Events.RateLimit.Blocked` (`{ player, eventName, limit, window }`) so external systems (kick, ban, analytics) can subscribe.
- A middleware that throws logs `MiddlewareError | event=<name> playerId=<id> err=<err>` and drops the packet.

## Network warning catalog

| Message | Meaning |
|---|---|
| `No handler for event:X` | Event fired but nobody is listening (event path). |
| `No invoke handler for: X` | Invoke fired but no handler registered (invoke path). |
| `Duplicate invoke handler for 'X' — replacing previous` | Second `Handle` for the same event (intentional replace). |
| `Handler error [X]: err` | A handler threw; isolated by pcall. |
| `Invoke handler error [X]: err` | An invoke handler threw; the client gets `nil`. |
| `Rejected packet from <p>, invalid eventName: <v>` | Inbound event name failed validation; dropped. |
| `middleware called next() multiple times` | Middleware misbehaving; the second `next` is ignored. |
| `Invoke 'X' failed: TIMEOUT` / `SERVER_ERROR` | Client-side invoke outcome (see [SPEC.md 4.7](SPEC.md#47-client-transport-details)). |

## Motion warnings

| Message | Meaning |
|---|---|
| `Tween already active: <path>` | Second concurrent tween on the same instance; returns `nil`. |
| `Invalid instance for tween` | Instance isn't a BasePart or a Model with a PrimaryPart. |
| `Network service missing` / `... network calls will be no-ops` | `TweenDriver.Init` didn't receive `services.Network`; tween replication is skipped. |
| `[Doors] Motion system not available` | The example `Doors` system couldn't get `Motion` (from `services` or the loader). |
