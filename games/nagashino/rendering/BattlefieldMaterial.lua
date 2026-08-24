-- Battlefield3D.lua 的材质侧配套：下发本作专属的逐材质开关，并复用引擎水面库。
-- 作为 LevelMesh 的 materialSender 传入（见 NagashinoScene:drawWorld）。
--
-- 只在 forward3d pass 用；shadow pass 的深度着色器不认识这些 uniform，
-- 不传 materialSender 就是不发，省掉一整趟无效的 hasUniform 查询。
local Fuc = require("engine.utils.Fuc")
local WaterMaterial = require("engine.rendering.WaterMaterial")

local BattlefieldMaterial = {}

function BattlefieldMaterial.send(shader, material)
    material = material or {}
    WaterMaterial.send(shader, material)
    -- 只有地面类材质吃战场状态图；栅栏/树叶/旗帜等立面材质不该被泥浆和血渍覆盖
    Fuc.safeSend(shader, "u_receivesBattlefieldState", material.receivesBattlefieldState and 1 or 0)
end

return BattlefieldMaterial
