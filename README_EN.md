# Love2dTest Engine

[简体中文](README.md) | English

Love2dTest Engine is a lightweight game-engine workspace built on [LÖVE 11.5](https://love2d.org/) and Lua for 2D, pseudo-3D, and real-time 3D prototypes. It keeps reusable engine code, complete games, samples, and offline tools separate, lets multiple games share one runtime, and can produce distributable Windows executables directly from the repository.

The workspace includes scene and resource management, a fixed-timestep loop, input and UI facilities, 2D/3D rendering utilities, optional Tiny ECS/physics adapters, service lifecycles, development diagnostics, and map, mesh, and release build pipelines.

## Highlights

- **Unified runtime**: a custom LÖVE loop with fixed-timestep simulation and complete event forwarding.
- **Scenes and layers**: a scene stack, pause/transition scenes, composable layers, and explicit enter/exit lifecycles.
- **Scoped resources**: manifest-driven fonts, images, audio, shaders, and canvases with separate global and per-scene ownership.
- **Rendering facilities**: 2D and 3D cameras, matrices and quaternions, OBJ and binary meshes, materials, shadows, post-processing, particles, and environment rendering.
- **Input and UI**: keyboard, mouse, controller, touch, and text-input forwarding with reusable buttons, dialogs, chat logs, and text fields.
- **Service system**: consistent start, frame-update, and stop lifecycles, including save support and an optional streaming LLM service.
- **Optional ECS integration**: reusable Tiny ECS and LÖVE Physics adapters without requiring games to use ECS.
- **Development diagnostics**: a debug overlay, timestep/frame limiting, GPU pass profiling, and extensible diagnostic providers.
- **Content pipelines**: JSON-to-`.smap` map compilation, OBJ-to-`.mesh` conversion, and project consistency validation.
- **Windows release builder**: select any game or sample, remove development content, and generate a fused EXE, runtime directory, and ZIP with a built-in custom-icon writer.

## Requirements

- LÖVE 11.5
- Windows PowerShell 5.1 or PowerShell 7 for the Windows release builder
- Node.js for map, mesh, and project validation tools

Add `love.exe` to `PATH`, or pass the LÖVE installation through `-LovePath` when building a release.

## Quick start

Run the default game from the repository root:

```powershell
love .
```

Select another game or sample without changing engine code:

```powershell
$env:LOVE_GAME = 'games.surveillance.Game'
love .

$env:LOVE_GAME = 'samples.cube3d.Game'
love .
```

Set the long-term default in `project.lua`:

```lua
return {
    name = "MyGame",
    game = "games.my_game.Game",
    globalManifest = "engine/assets/manifest/global.lua",
    testModule = "tests.run",
    debugOverlay = true,
}
```

## Repository layout

| Path | Purpose |
| --- | --- |
| `main.lua` | Minimal bootstrap that installs `project.lua` into the engine. |
| `conf.lua` | LÖVE window, console, and development/release configuration. |
| `project.lua` | Current project name, game module, global manifest, test, and debug settings. |
| `engine/` | Game-independent runtime, managers, services, rendering, UI, input, and shared assets. |
| `games/` | Complete distributable game packages that own their code and assets. |
| `samples/` | Independent examples and feature-validation projects. |
| `libs/` | Third-party Lua dependencies. |
| `tests/` | Engine and architecture tests. |
| `tools/` | Map, mesh, validation, and Windows release tools. |
| `docs/` | Additional architecture and content-production documentation. |

Dependencies flow in one direction:

```text
main.lua -> project.lua -> engine.Engine -> selected Game
                                      Game -> engine APIs
```

`engine/` must not import a concrete `games/` or `samples/` module. See [docs/architecture.md](docs/architecture.md) for the complete boundary and resource-ownership rules.

## Game module contract

Every game or sample exposes the same interface through `Game.lua`:

```lua
local Game = { id = "my_game" }

function Game:start(context, args)
    -- Optional: register game services.
end

function Game:createInitialScene(context, args)
    return require("games.my_game.scenes.MainScene").new(context)
end

function Game:stop(context)
    -- Optional: clean up game-level state.
end

return Game
```

The engine `context` exposes scene management, resource management, diagnostics, the service registry, save support, project metadata, and the selected game.

## Resource rules

- Shared engine assets belong in `engine/assets/`.
- Game- or sample-specific assets belong inside their owning package.
- Load static assets through manifests; do not create GPU resources in `draw()`.
- Each scene has an isolated resource scope that is released when the scene exits.
- Register runtime-generated resources through `ResourceManager:register()`.
- Recreate screen-sized canvases from `resize` handlers.

## Included targets

The release builder discovers packages that contain `Game.lua`. List the current targets with:

```powershell
.\tools\build_release.ps1 -List
```

The repository currently contains:

- Games: `games/nagashino`, `games/surveillance`
- Samples: `samples/breakout`, `samples/cube3d`, `samples/musou`, `samples/nagashino`, `samples/raycast`, `samples/shader_maze`

## Tests and project validation

Run the Lua test suite:

```powershell
love . --test
```

Validate architecture dependencies, manifest paths, and compiled maps:

```powershell
node tools/validate_project.js
```

## Content tools

### Map compilation

JSON files are the map sources; the runtime uses compressed, chunked `.smap` files:

```powershell
node tools/build_maps.js
node tools/build_maps.js --check
```

`--check` does not modify the repository and is intended for CI and pre-release stale-map checks.

Compile one map directly with:

```powershell
node tools/pack_map.js input.json output.smap
```

### Mesh compilation

Convert a Wavefront OBJ into the engine's `SMSHBIN1` binary mesh format to avoid parsing text models at runtime:

```powershell
node tools/obj2mesh.js input.obj output.mesh
```

See [docs/blender_export.md](docs/blender_export.md) for the Blender content workflow.

## Windows release builds

`tools/build_release.ps1` fixes the selected game module and creates a portable release directory. Release builds disable the console, debug overlay, and test entry point, and exclude tests, editors, build scripts, source art, unselected games, and other development-only content.

```powershell
# Build a complete game
.\tools\build_release.ps1 games/nagashino -Name Nagashino -Version 1.0.0

# Build a sample
.\tools\build_release.ps1 samples/cube3d -Name CubeDemo -Version 0.2.0

# Embed a custom icon
.\tools\build_release.ps1 games/nagashino `
  -Name Nagashino `
  -Version 1.0.0 `
  -Icon .\game.ico `
  -Force
```

Default output:

```text
dist/<Name>/<Name>.exe
dist/<Name>/*.dll
dist/<Name>-<Version>-windows-x64.zip
```

Common options:

| Option | Description |
| --- | --- |
| `-List` | List every buildable game and sample. |
| `-Name <name>` | Set the product, executable, and output-directory name. |
| `-Version <version>` | Set the release version and build metadata. |
| `-OutputDirectory <path>` | Change the output root; defaults to `dist`. |
| `-LovePath <path>` | Specify `love.exe` or a LÖVE installation directory. |
| `-Icon <file.ico>` | Embed a multi-resolution Windows ICO directly, with no external tool. |
| `-SkipArchive` | Keep only the portable directory and skip the final ZIP. |
| `-KeepLove` | Keep the intermediate `.love` archive. |
| `-Force` | Replace an existing output with the same name. |

For best Windows results, include 16, 32, 48, and 256-pixel layers in the ICO. Keep the generated DLL files beside the executable when distributing or running the release.

## Development principles

- Games depend on the engine; the engine never depends on a concrete game.
- Put reusable mechanisms in `engine/` and keep gameplay rules and content in their owning game or sample.
- Give resources, scenes, services, and GPU objects clear owners and cleanup paths.
- Treat map and mesh text files as production sources and compiled formats as runtime/release assets.
- Run the tests, `validate_project.js`, and the map `--check` before committing or shipping.
