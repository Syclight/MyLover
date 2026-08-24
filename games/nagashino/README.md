# 长筱之战：设乐原

这是一个可游玩的长筱之战战术场景：武田军冲锋，织田・德川联军依托马防柵实施三段击。

当前版本包含：

- Takeda, Oda, and Tokugawa banner textures with simple crest placeholders.
- Banner cloth is exported as UV-mapped double-sided planes so crest textures are visible in engine.
- Low-poly ashigaru with jingasa helmets and teppo barrels.
- Low-poly mounted Takeda riders with horse legs, kabuto silhouettes, and yari.
- Horse fences face across the charge lane, with angled anti-cavalry stakes pointing toward the Takeda approach.
- Natural environment set dressing: stream, rear hills, and tree lines.
- Gun smoke markers along the Oda fire line.
- 238 名批量渲染的表现单位、武田冲锋与火枪阵齐射动画。
- 伤亡统计、暂停、战役重开与胜负状态。

## Regenerate Art

Regenerate the procedural water/leaf textures (tileable water normal map,
leaf-cluster albedo + normal; used by `water_stream` and `foliage_*` materials):

```powershell
node games/nagashino/tools/gen_textures.js
```

Run Blender headless to rebuild the editable `.blend` and exported OBJ:

```powershell
& 'D:\Softwares\Blender\blender.exe' --background --python games\nagashino\tools\create_blockout.py
```

Convert the OBJ to the runtime mesh format:

```powershell
node tools/obj2mesh.js games/nagashino/assets/models/battlefield.obj games/nagashino/assets/models/battlefield.mesh
```

## Object Naming

- Rendered objects use ordinary names such as `oda_horse_fence_1_post_1`.
- Collision objects end with `_col`, for example `terrain_col`.
- Gameplay trigger volumes end with `_trigger`, for example `takeda_charge_lane_trigger`.
- Current scripted triggers: `command_view_trigger`, `takeda_charge_lane_trigger`,
  and `oda_fireline_trigger`.

`LevelMesh` keeps all objects in `allObjects`, exposes `_col` objects through
`colliders`, exposes `_trigger` objects through `triggers`, and skips both in rendering.

## Materials

Material names come from Blender `usemtl` values and are mapped in
`assets/levels/nagashino.lua`.

Current blockout materials:

- `grass_battlefield`
- `mud_road`
- `wood_dark`
- `cloth_takeda`
- `cloth_oda`
- `cloth_tokugawa`
- `ashigaru_cloth`
- `takeda_armor`
- `horse_brown`

The current textures are simple generated placeholders. Replace them with real
albedo/normal/PBR maps without changing the level mesh.
