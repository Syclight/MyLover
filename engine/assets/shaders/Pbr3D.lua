-- 引擎 PBR 前向着色器：自定义 MVP、方向光 + 半球环境光、法线/PBR/AO 贴图、
-- 阴影、曝光与高度雾。不含任何游戏专属效果。
--
-- shader 模块模式（正式约定）：.lua 模块返回 GLSL 源码串，经 manifest 的
-- shaders { module = ... } 加载；源码内可用 #include 引公共函数库
-- （ShaderPreprocessor 展开，路径相对模块目录或工程根）。
--
-- 需要在这套光照上叠加自己的表面效果时，不要复制本文件——在游戏包里写一个
-- 变体，#define hook 后 include 同一份核心。契约与范例见
-- engine/assets/shaders/include/pbr3d.glsl 头部注释。
return [[
#include "engine/assets/shaders/include/pbr3d.glsl"
]]
