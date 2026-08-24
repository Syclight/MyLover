# Blender 导出约定（3D 关卡/模型）

> 工具链方针（P3）：**不自研 3D 编辑器**。`editor/` 是 2D tile 编辑器，只服务
> 2D 地图（SMAPBIN1，见 `tools/pack_map.js`）；3D 关卡与模型在 Blender 里做，
> 靠本文档的导出约定 + `tools/obj2mesh.js` 离线转换接入引擎。

## 管线一览

```
Blender ──(OBJ 导出)──> level.obj ──(node tools/obj2mesh.js)──> level.mesh (SMSHBIN1)
                                                                    │
运行时：MeshBin.load ── Data 直灌 setVertices/setVertexMap ──> love Mesh（零解析）
开发迭代：ObjLoader.load 直接热读 .obj（免转换，改完即见）
```

## 坐标系与单位

| 项 | Blender | 引擎（LÖVE/GL 惯例） | 处理 |
| --- | --- | --- | --- |
| 上方向 | +Z | +Y | 导出设置 `Up = Y`（OBJ 导出器默认） |
| 前方向 | -Y | -Z（相机看向 -Z） | 导出设置 `Forward = -Z`（默认） |
| 手性 | 右手 | 右手 | 无需处理 |
| 单位 | 1 BU | 1 引擎单位 = 1 米 | 建模按米；导出 Scale = 1.00 |

导出前 **Object → Apply → All Transforms（Ctrl+A）**：obj2mesh 不处理对象级
变换，OBJ 里的顶点必须已是世界坐标。

## OBJ 导出勾选（File → Export → Wavefront）

- ✅ **Triangulate Faces**——引擎侧扇形三角化只对凸多边形安全，交给 Blender 保险
- ✅ **Write Normals**——缺 vn 时转换器按面法线补齐（全硬边），一般不是你想要的
- ✅ **Include UVs**——UV 原点差异（Blender 左下 / LÖVE 左上）由转换链自动翻转 v
- ✅ Material Groups——`.mtl` 文件本身不解析，但 `usemtl` 的材质名会保留到对象表；
  贴图/颜色/PBR 参数等 material 定义在 level manifest 里配
- ✅ Objects as OBJ Objects——每个 Blender Object 成为对象表一段（见下）

环绕方向：OBJ 默认从外侧看 CCW，与引擎约定一致（`cullMode = "back"` +
`Camera3D:frontFaceWinding()`）。Blender 里法线朝外即可（Mesh → Normals →
Recalculate Outside）。

## 对象表（关卡分段）

`o` / `g` 行把关卡切成对象，转换后写进 SMSHBIN1 头部：

```lua
objects = {
    { name = "room_east", indexStart = 1,   indexCount = 522,
      material = "wall_plaster",
      center = { 4.0, 1.5, -2.0 }, boundingRadius = 5.2 },
    ...
}
```

- `indexStart`/`indexCount` 为 1 基，可直接喂 `Mesh:setDrawRange` 做**分对象
  绘制**；`center` + `boundingRadius`（对象 AABB 外接球）配合
  `Camera3D:isSphereVisible` 做**分对象视锥剔除**。
- `material` 来自 OBJ 的 `usemtl` 名称。运行时用 level manifest 把名称映射到
  `{ albedo, normal, pbr, color, metallic, roughness, ao, normalScale }`；转换器不读
  `.mtl`，避免把 DCC 工具路径耦合进运行时。
- 命名约定：`*_col` 碰撞体、`*_trigger` 触发区。它们仍写入对象表并暴露为
  `LevelMesh.colliders` / `LevelMesh.triggers`，但默认不参与渲染。

## Level manifest

关卡 manifest 是一个 Lua 表，负责把 mesh、material、对象过滤规则连起来：

```lua
return {
  mesh = "samples/cube3d/assets/models/level", -- 自动优先 .mesh，缺失回退 .obj
  render = {
    skipSuffixes = { "_col", "_trigger" },
    colliderSuffix = "_col",
    triggerSuffix = "_trigger",
  },
  materials = {
    wall_plaster = {
      albedo = "wall_albedo",
      normal = "wall_normal",
      pbr = "wall_pbr",
      color = { 0.8, 0.82, 0.86, 1 },
      metallic = 0.0, roughness = 0.65, ao = 1.0, normalScale = 0.5,
    },
  },
}
```

`albedo` / `normal` / `pbr` 是 `ResourceManager` 里的图片资源名。当前 PBR packed map
约定为：R = metallic，G = roughness，B = ambient occlusion。

## 转换与加载

```bash
node tools/obj2mesh.js assets/models/level.obj assets/models/level.mesh
```

```lua
local LevelMesh = require("engine.rendering.LevelMesh")
local level, source = LevelMesh.loadFromManifest("samples/cube3d/assets/levels/demo.lua", ResourceManager)
```

推荐照 `samples/cube3d/scenes/Cube3DScene.lua` 的关卡加载路径：优先 `.mesh`、
缺失回退 `.obj`，再交给 `LevelMesh:drawObjects` 做 material 绑定和逐对象剔除。

## 容量红线

- 顶点数 ≤ 65535 时索引流用 uint16（自动），超过自动升 uint32。
- 顶点格式固定 `pos3 + uv2 + norm3`（32 字节/顶点）。要加顶点色/切线时，
  升级 SMSHBIN 版本号并同步改三处：`ObjLoader.VERTEX_FORMAT`、
  `MeshBin`、`tools/obj2mesh.js`。
