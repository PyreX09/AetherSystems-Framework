<div align="center">

# AetherSystems

**A minimalist module framework for Roblox.**

It loads your modules in dependency order and gets out of the way.

`MIT` - [License](LICENSE) - [Support the project](https://ko-fi.com/jirawatphundthawandee) - [DevForum post](https://devforum.roblox.com/t/open-source-aethersystems-a-minimalist-module-network-framework/4813570/1)

</div>

---

## What is this?

AetherSystems is a small framework that organizes your Roblox game's server and client code into **systems** - modules that declare what they need and get started in the right order automatically.

If you've ever had scripts that break because "this needs to load before that", AetherSystems solves it. You write a module, tell it which other modules it depends on, and the framework:

1. **Finds** your modules (by folder, no central list to maintain),
2. **Orders** them by their dependencies,
3. **Starts** each one in order, handing it the modules it asked for.

That's the whole idea. There are no base classes to extend, no code generation - a module is a normal Roblox `ModuleScript`, and you `require()` it like you already do.

> **Philosophy:** *Only build what solves a real pain point today.*
> If a piece of this framework exists, it is because something broke without it.

## What's included

| Piece | What it does |
|---|---|
| **Loader** | Discovers your systems, resolves dependencies, starts them in order. Works on the server and the client. |
| **Network** | A clean API over Roblox remotes - events and invokes with named handlers, middleware, and built-in rate limiting. |
| **Motion** | Server-driven tweens that play smoothly on every client (doors, elevators, animations - anything that moves). |
| **Logger** | Neat, aligned log output with levels and profiling. |
| **Janitor** | A tiny helper that cleans up connections and instances for you. |
| **RaycastUtil** | A named cache of reusable `RaycastParams` objects for line-of-sight checks. |

Everything else is *your* game code. There are two reference systems to study: push doors (a simple `Motion` use case) and a tracking turret (a use case that exercises `RaycastUtil` + `Motion` + `Janitor` + `Logger` together).

## Quick start

### 1. Drop it into Studio

In Roblox Studio, create these containers (or copy them from a place that already uses AetherSystems):

```
ServerScriptService/AetherSystems      <- the loader + services (server)
ReplicatedStorage/AetherShared         <- shared utilities + remotes (both sides)
StarterPlayer/StarterPlayerScripts/AetherClient   <- client loader + services
```

### 2. Write your first system

Inside `ServerScriptService/AetherSystems/Systems/`, create a folder called `Greeter` with a `ModuleScript` inside it:

```lua
local Greeter = {}

Greeter.Descriptor = {
    Name = "Greeter",
    Dependencies = { "Network" },   -- optional: modules you need, by name
}

function Greeter.Init(services)
    local Network = services.Network
    print("Hello from Greeter!")
end

return Greeter
```

### 3. Press play

That's it. `Bootstrap` (the script in `Core/`) starts everything: your system is discovered, ordered after its dependencies, and `Init` is called. Add more systems the same way - the framework figures out the order.

### 4. Talk to your systems

From any other script, get a system through the loader:

```lua
local Loader = require(game:GetService("ServerScriptService").AetherSystems.Core.AetherLoader)
local Network = Loader.Get("Network")
```

## A quick tour

```
ServerScriptService/AetherSystems
|-- Core/          the loader itself (you normally don't touch this)
|-- Services/      built-in services: Network, Motion
|-- Systems/       your game features go here
|-- Config/        settings (e.g. rate limits)
`-- Events/        runtime events (e.g. RateLimit.Blocked)

ReplicatedStorage/AetherShared
|-- Event/Network/  the two remotes every message goes through
|-- Utils/          NetworkCore, Logger, Janitor, RaycastUtil (shared by server & client)
`-- TagList/        documented CollectionService tags

StarterPlayer/StarterPlayerScripts/AetherClient
|-- Loader/         client boot loader
|-- Services/       client-side Network + Motion
`-- Systems/        client game features
```

## Simple examples

**Send an event to every player:**

```lua
-- inside any system's Init(services)
local Network = services.Network
Network.FireAll("Announcement.Global", "Server restarts in 5 minutes")
```

**Listen for a click and move a door (server):**

```lua
function Doors.Init(services)
    local Network = services.Network
    local Motion  = services.Motion

    Network.On("Door.Clicked", function(player, door)
        Motion.Move(door, { Goal = CFrame.new(0, 10, 0), Duration = 0.8 })
    end)
end
```
[**Motion Demo**](https://github.com/PyreX09/AetherSystems-Framework/blob/main/Gif/Motion%20Demo1.gif)

**Log something with style:**

```lua
local Logger = require(game:GetService("ReplicatedStorage").AetherShared.Utils.Logger)
Logger:Info("Shop", "Item purchased", itemId)
```

**Reuse RaycastParams instead of rebuilding them (RaycastUtil):**

```lua
local RaycastUtil = require(game:GetService("ReplicatedStorage").AetherShared.Utils.RaycastUtil)

-- register once; Get() always returns the same RaycastParams object
RaycastUtil.Register("Enemy.LOS", {
    FilterType = Enum.RaycastFilterType.Exclude,
    FilterDescendantsInstances = {},
})

-- Update() mutates it in place, so pre-held references stay in sync.
-- Call Raycast immediately after - no yields between the two.
RaycastUtil.Update("Enemy.LOS", { FilterDescendantsInstances = { character } })
local hit = workspace:Raycast(origin, direction, RaycastUtil.Get("Enemy.LOS"))
```

**A tracking turret (server, the `Combat/Turret` use case):**

```lua
-- Tag a Model with CollectionService tag "Turret". Give it a "Base" part
-- and a "Head" BasePart - the Head rotates to face the nearest player
-- within 60 studs that it has a clear line of sight to.
CollectionService:AddTag(turretModel, "Turret")

-- The system in ServerScriptService/AetherSystems/Systems/Combat/Turret
-- is a use case that tests the framework systems working together:
-- RaycastUtil for LOS checks, Motion.Move to rotate the Head toward the
-- target, Janitor for per-turret cleanup, Logger for transitions.
```

## Rules of the road

- **Fail loud, fail early.** On the server, a missing dependency or a circular dependency stops boot and the error tells you exactly which system and which dependency caused it. On the client, broken systems are skipped and reported - your game still starts.
- **One module, one job.** Systems depend on each other by name; `Init(services)` hands each system exactly what it asked for.
- **Two remotes, not hundreds.** All network traffic flows through one `RemoteEvent` and one `RemoteFunction`, addressed by event name.

## Documentation

The docs are split into focused guides. Start at the [**docs index**](docs/README.md) for reading order and a glossary, or jump straight in:

| Doc | Read it for |
|---|---|
| [**Architecture**](docs/ARCHITECTURE.md) | How the framework is put together, boot sequences, data flow |
| [**API Reference**](docs/API.md) | Every function: loader, Network, Motion, Logger, Janitor, config |
| [**Conventions**](docs/CONVENTIONS.md) | How to write systems that fit in - naming, module contract, style |
| [**Spec & Baseline**](docs/SPEC.md) | The precise contracts: dependency rules, network protocol, rate limiting, motion protocol |
| [**Diagnostics**](docs/DIAGNOSTICS.md) | Every error message, the boot summary, tracing, and dev tools |
| [**Releases**](RELEASES.md) | Changelog for every version (V.1.1.0 and up) |

## Status

In active development. This README and the docs describe the code as it exists right now (`V.1.1.0`).

---

<p align="center"><sub>Made with care for Roblox developers - MIT licensed - [Support on GitHub or Ko-fi](FUNDING.yml)</sub></p>
