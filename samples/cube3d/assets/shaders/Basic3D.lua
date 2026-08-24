-- 基础 3D 前向着色器：直接用引擎 PBR 核心，不加任何本 sample 专属效果。
--
-- 本文件曾是 engine/assets/shaders/Pbr3D.lua 的逐字节副本（327 行），
-- 其中战场状态与水面路径本 sample 从不使用。现在两边共用同一份
-- engine/assets/shaders/include/pbr3d.glsl，改光照只需改一处。
return [[
#include "engine/assets/shaders/include/pbr3d.glsl"
]]
