# AetherSystems Documentation

Welcome to the AetherSystems docs. Everything here describes the code as it exists today (**V.1.0.0**).

## The guides

| Guide | Read it for |
|---|---|
| [**Architecture**](ARCHITECTURE.md) | How the framework is put together - layout, component responsibilities, boot sequences, data flow |
| [**API Reference**](API.md) | Every public function: loader, Network, Motion, Logger, Janitor, config |
| [**Conventions**](CONVENTIONS.md) | How to write systems that fit in - module contract, naming, folder rules, code style |
| [**Spec & Baseline**](SPEC.md) | The precise contracts: dependency rules, network protocol, rate limiting, motion protocol, config schema |
| [**Diagnostics**](DIAGNOSTICS.md) | Every error message, the client boot summary, network tracing, and dev tools |

## Where to start

**New to AetherSystems** (writing your first system):

1. [**Conventions**](CONVENTIONS.md) - the module contract (`Descriptor`, `Init(services)`) and how to add a system.
2. [**API Reference**](API.md) - what you can call once you have `services`.

**Trying to understand the framework**:

1. [**Architecture**](ARCHITECTURE.md) - the big picture and boot sequence.
2. [**Spec & Baseline**](SPEC.md) - the exact rules the loader and services follow.

**Debugging a problem**:

1. [**Diagnostics**](DIAGNOSTICS.md) - error messages, boot summary, tracing, dev tools.
2. [**Spec & Baseline**](SPEC.md) - to check the behavior you're seeing is actually the contract.

## Cross-cutting topics

- **Module contract** - [Conventions](CONVENTIONS.md#module-contract) - [Spec 2](SPEC.md#2-module-descriptor)
- **Dependency resolution** - [Architecture](ARCHITECTURE.md#dependency-resolution-rules-recap) - [Spec 3](SPEC.md#3-dependency-resolution)
- **Network protocol** - [API](API.md#networkserver-server) - [Spec 4](SPEC.md#4-network-protocol)
- **Motion protocol** - [API](API.md#tweendriver-server) - [Spec 5](SPEC.md#5-motion-protocol)
- **Rate limiting** - [API](API.md#networkconfig-server) - [Spec 4.6](SPEC.md#46-rate-limiting)
- **Logging** - [API](API.md#logger-shared) - [Spec 8](SPEC.md#8-logger-contract)
- **Cleanup** - [API](API.md#janitor-shared)
- **Tracing** - [Diagnostics](DIAGNOSTICS.md#network-trace) - [Spec 7](SPEC.md#7-tracing-debug)

## Quick glossary

| Term | Meaning |
|---|---|
| **System / Service** | A module discovered by the loader. "Services" are reusable modules in `Services/`; "systems" are game features in `Systems/`. The loader treats them identically. |
| **Primary module** | The module the loader picks for a folder (server: first module found; client: `FolderName` -> `FolderNameClient` -> `FolderNameServer` -> alphabetical). |
| **Registry name** | The key a system is known by - `Descriptor.Name` or the folder name. Used in `Dependencies`, `services.X`, and `Loader.Get("X")`. |
| **Descriptor** | The `{ Name, Dependencies }` table a module may return to describe itself. |
| **`services`** | The table `Init(services)` receives - every successfully initialized module, keyed by registry name. |
| **Event name** | The string that addresses a message over the shared remotes (max 64 chars, `Domain.Action` style). |
| **Packet** | The server-side message object passed through middleware: `{ player, eventName, args }`. |

## Keeping the docs honest

The docs describe the code as it is. If you change behavior, update the matching guide **and** the baseline in [SPEC.md](SPEC.md) - the spec exists so deviations from it are visible breaking changes.

---

<- Back to [the main README](../README.md)
