# Love2dTest Engine

简体中文 | [English](README_EN.md)

Love2dTest Engine 是一个基于 [LÖVE 11.5](https://love2d.org/) 与 Lua 的轻量游戏引擎工作区，面向 2D、伪 3D 和实时 3D 游戏原型。仓库将通用引擎、正式游戏、示例项目和离线工具明确分离，可在同一套运行时中切换游戏，并能直接生成 Windows 发行版 EXE。

当前仓库包含场景与资源管理、固定时间步循环、输入与 UI、2D/3D 渲染设施、可选 Tiny ECS/物理适配、服务生命周期、诊断工具，以及地图、网格和发行版构建流水线。

## 主要特性

- **统一运行时**：自定义 LÖVE 主循环、固定时间步模拟和完整事件转发。
- **场景与层系统**：场景栈、暂停/过渡场景、可组合的游戏层及明确的进入/退出生命周期。
- **资源作用域**：清单驱动的字体、图像、音频、着色器和 Canvas 加载；全局资源与场景资源分别管理并自动释放。
- **渲染设施**：2D 相机、3D 相机、矩阵/四元数、OBJ 与二进制网格、材质、阴影、后处理、粒子和环境渲染。
- **输入与 UI**：键鼠、手柄、触控及文本输入转发，包含按钮、对话框、聊天记录和文本输入等组件。
- **服务系统**：统一的启动、逐帧更新和停止生命周期，内置存档服务及可选的流式 LLM 服务。
- **可选 ECS 集成**：提供 Tiny ECS 与 LÖVE Physics 的通用适配器，不强制游戏采用 ECS 架构。
- **开发诊断**：调试面板、时间步/帧率控制、GPU Pass 分析和可扩展诊断数据提供者。
- **内容流水线**：JSON 地图编译为 `.smap`，OBJ 转换为运行时 `.mesh`，并提供项目一致性检查。
- **Windows 发行工具**：选择任意 game 或 sample，排除开发内容，生成融合 EXE、运行库目录及 ZIP，支持内置自定义图标。

## 环境要求

- LÖVE 11.5
- Windows PowerShell 5.1 或 PowerShell 7（Windows 发行工具）
- Node.js（地图、网格和项目验证工具）

将 `love.exe` 加入 `PATH`，或在构建发行版时使用 `-LovePath` 指定 LÖVE 安装目录。

## 快速开始

在仓库根目录运行默认游戏：

```powershell
love .
```

无需修改引擎代码即可临时选择其他游戏或示例：

```powershell
$env:LOVE_GAME = 'games.surveillance.Game'
love .

$env:LOVE_GAME = 'samples.cube3d.Game'
love .
```

长期默认目标在 `project.lua` 中配置：

```lua
return {
    name = "MyGame",
    game = "games.my_game.Game",
    globalManifest = "engine/assets/manifest/global.lua",
    testModule = "tests.run",
    debugOverlay = true,
}
```

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `main.lua` | 最小启动入口，将 `project.lua` 安装到引擎。 |
| `conf.lua` | LÖVE 窗口、控制台和开发/发行模式配置。 |
| `project.lua` | 当前项目名称、游戏模块、全局清单、测试和调试配置。 |
| `engine/` | 与具体游戏无关的运行时、管理器、服务、渲染、UI、输入和公共资源。 |
| `games/` | 可发行的完整游戏包，每个包拥有自己的代码和资源。 |
| `samples/` | 独立示例和功能验证项目。 |
| `libs/` | 第三方 Lua 依赖。 |
| `tests/` | 引擎与架构测试。 |
| `tools/` | 地图、网格、验证及 Windows 发行版构建工具。 |
| `docs/` | 架构和内容制作补充文档。 |

依赖方向保持单向：

```text
main.lua -> project.lua -> engine.Engine -> selected Game
                                      Game -> engine APIs
```

`engine/` 不应导入任何具体 `games/` 或 `samples/` 模块。更完整的边界与资源所有权规则参见 [docs/architecture.md](docs/architecture.md)。

## 游戏模块约定

每个游戏或示例通过 `Game.lua` 暴露统一接口：

```lua
local Game = { id = "my_game" }

function Game:start(context, args)
    -- 可选：注册游戏服务。
end

function Game:createInitialScene(context, args)
    return require("games.my_game.scenes.MainScene").new(context)
end

function Game:stop(context)
    -- 可选：清理游戏级状态。
end

return Game
```

`context` 提供场景管理器、资源管理器、诊断系统、服务注册表、存档服务、项目配置和当前游戏信息。

## 资源约定

- 引擎公共资源放在 `engine/assets/`。
- 游戏或示例专用资源放在其包目录内。
- 静态资源通过资源清单加载，不在 `draw()` 中创建 GPU 资源。
- 场景资源由独立作用域管理；场景退出时统一释放。
- 运行时生成的资源使用 `ResourceManager:register()` 纳入生命周期管理。
- 随窗口尺寸变化的 Canvas 通过 `resize` 处理器重新创建。

## 内置目标

发行工具会自动扫描包含 `Game.lua` 的包。当前目标可通过以下命令查看：

```powershell
.\tools\build_release.ps1 -List
```

仓库当前包含：

- Games：`games/nagashino`、`games/surveillance`
- Samples：`samples/breakout`、`samples/cube3d`、`samples/musou`、`samples/nagashino`、`samples/raycast`、`samples/shader_maze`

## 测试与项目验证

运行 Lua 测试：

```powershell
love . --test
```

检查架构依赖、资源清单路径和已编译地图是否最新：

```powershell
node tools/validate_project.js
```

## 内容构建工具

### 地图编译

JSON 是地图源文件，运行时优先读取压缩、分块的 `.smap`：

```powershell
node tools/build_maps.js
node tools/build_maps.js --check
```

`--check` 不修改仓库，用于 CI 或发行前检测过期的 `.smap`。

也可以编译单个地图：

```powershell
node tools/pack_map.js input.json output.smap
```

### 网格编译

将 Wavefront OBJ 离线转换为引擎的 `SMSHBIN1` 二进制网格，避免运行时解析文本模型：

```powershell
node tools/obj2mesh.js input.obj output.mesh
```

Blender 内容制作流程参见 [docs/blender_export.md](docs/blender_export.md)。

## Windows 发行版构建

`tools/build_release.ps1` 会固定所选游戏模块并生成便携发行目录。发行构建将关闭控制台、调试覆盖层和测试入口，并排除测试、编辑器、构建脚本、原始美术工程及未选游戏。

```powershell
# 构建正式游戏
.\tools\build_release.ps1 games/nagashino -Name Nagashino -Version 1.0.0

# 构建示例
.\tools\build_release.ps1 samples/cube3d -Name CubeDemo -Version 0.2.0

# 使用自定义图标
.\tools\build_release.ps1 games/nagashino `
  -Name Nagashino `
  -Version 1.0.0 `
  -Icon .\game.ico `
  -Force
```

默认输出：

```text
dist/<Name>/<Name>.exe
dist/<Name>/*.dll
dist/<Name>-<Version>-windows-x64.zip
```

常用参数：

| 参数 | 说明 |
| --- | --- |
| `-List` | 列出所有可构建的 game 和 sample。 |
| `-Name <name>` | 设置产品名、EXE 文件名和输出目录名。 |
| `-Version <version>` | 设置发行版本并写入构建元数据。 |
| `-OutputDirectory <path>` | 更改输出根目录，默认为 `dist`。 |
| `-LovePath <path>` | 指定 `love.exe` 或 LÖVE 安装目录。 |
| `-Icon <file.ico>` | 将多尺寸 Windows ICO 直接写入 EXE，无需外部工具。 |
| `-SkipArchive` | 不生成最终 ZIP，只保留便携目录。 |
| `-KeepLove` | 保留中间 `.love` 文件。 |
| `-Force` | 覆盖同名输出。 |

建议 ICO 包含 16、32、48 和 256 像素图层。发行目录中的 EXE 必须与工具复制的 DLL 保持在同一目录。

## 开发原则

- 游戏依赖引擎，不能让引擎依赖具体游戏。
- 通用机制放入 `engine/`，玩法规则和内容留在所属 game/sample。
- 资源、场景、服务和 GPU 对象必须有清晰的所有者与释放路径。
- 地图与网格的文本源文件用于制作，编译格式用于运行时和发行版。
- 提交或发行前运行测试、`validate_project.js` 和地图 `--check`。
