# Engine and game boundaries

The repository is a small engine workspace containing one active game and several samples.

## Dependency direction

```text
main.lua -> project.lua -> engine.Engine -> selected Game
                                      Game -> engine APIs
```

`engine/` must never require `games/`. A game is selected by `project.lua` and passed to the engine through this contract:

- `Game.id`: stable project identifier.
- `Game:createInitialScene(context)`: returns a scene instance.
- `Game:start(context, args)`: optional service registration.
- `Game:stop(context)`: optional service cleanup.

The engine context exposes scene management, resource management, diagnostics, a service registry, and project metadata. Games register optional services during `Game:start`; the engine starts, updates, and stops them independently of scene visibility.

## Ownership

| Owner | Responsibilities |
| --- | --- |
| `engine/` | app loop, scene stack, resource scopes, service lifecycle, diagnostics, reusable UI/rendering/integrations, and shared assets |
| `games/surveillance/` | apartment rendering, interactions, inventory presentation, terminal/LLM gameplay, game data and assets |
| `samples/` | optional prototype packages, each owning its Game entry, views, effects, and assets |

The former `src/` transition namespace has been removed. Canonical code lives under `engine/`, `games/`, or `samples/`; architecture tests reject new `require("src...")` dependencies.

Tiny ECS is optional. Reusable Tiny/LÖVE Physics adapters live under `engine/integrations/tiny`; game-specific input, collision rules, and entity factories remain inside their sample or game package.

LLM transport is an optional engine service: `LLMService`, its worker protocol, and backend adapters are reusable infrastructure. Prompts, personas, interrogation sessions, channel direction, and transcript presentation remain game-owned policy.

Resource ownership follows the same boundary: engine-wide resources live in `engine/assets`; package-specific resources live beside their owning game/sample. The root does not act as a mixed asset bucket.

## What remains game-specific

The apartment ray-marcher is a renderer owned by Surveillance, not an engine renderer. Generic post-processing, timing, resource lifetime, and profiling can move into engine services; furniture, books, climate control, and terminal rules remain in the game.

## Next extraction seam

`games/surveillance/layers/RaycastLayer.lua` still combines rendering and simulation. Split it behind the existing scene state in this order:

Completed extractions:

- `PlayerController`
- `InteractionSystem`
- `FurniturePoseSystem`
- `PlacementSystem`
- `ItemWorldSystem`
- `ApartmentRenderer`

The former `RaycastLayer` now coordinates world initialization and these components. Future work can extract map/world construction if additional apartment levels need different builders.

These are ordinary composed systems; they do not need to be ECS systems.
