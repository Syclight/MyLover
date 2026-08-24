-- engine/assets/shaders/include/water.glsl 的材质侧配套：把关卡清单里的水面字段
-- 下发成 uniform。作为 LevelMesh 的 materialSender 使用：
--
--   level:drawObjects({ ..., materialSender = WaterMaterial.send })
--
-- 独立成模块而不是塞进 LevelMesh.applyMaterial：水面是可选特性，只用引擎基础
-- PBR 的场景不该为它多发四个 uniform，更不该让引擎核心认识 shallowColor 这类字段。
local Fuc = require("engine.utils.Fuc")

local WaterMaterial = {}

WaterMaterial.DEFAULT_FLOW = { 1, 0 }
WaterMaterial.DEFAULT_SHALLOW = { 0.12, 0.30, 0.28 }
WaterMaterial.DEFAULT_DEEP = { 0.035, 0.11, 0.16 }

-- 关卡清单中 type = "water" 的材质走水面着色路径，其余材质原样走 PBR。
function WaterMaterial.send(shader, material)
    material = material or {}
    Fuc.safeSend(shader, "u_waterSurface", material.type == "water" and 1 or 0)
    Fuc.safeSend(shader, "u_flowDirection", material.flowDirection or WaterMaterial.DEFAULT_FLOW)
    Fuc.safeSend(shader, "u_waterShallowColor", material.shallowColor or WaterMaterial.DEFAULT_SHALLOW)
    Fuc.safeSend(shader, "u_waterDeepColor", material.deepColor or WaterMaterial.DEFAULT_DEEP)
end

return WaterMaterial
