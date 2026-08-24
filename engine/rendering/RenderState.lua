-- 渲染状态纪律：love.graphics 是全局状态机，2D/UI 代码从不碰
-- setDepthMode/setMeshCullMode/setFrontFaceWinding——一旦 3D pass 忘记还原，
-- UI 层就花屏。约定：本工程的 2D 基线状态是固定的（见 reset），
-- 任何一趟 3D/离屏 pass 结束后必须回到该基线，而不是"恢复到之前碰巧是什么"。
-- 这让还原成本恒定、且不依赖调用方自觉——RenderPipeline 在每个 pass 出口强制调用。
--
-- 用法（手写 pass 时）：
--   RenderState.apply({ shader = s, depthMode = { "lequal", true }, cullMode = "back" })
--   ... 绘制 ...
--   RenderState.reset()  -- 强制回到 2D 基线（含 setCanvas() 回 backbuffer）
local RenderState = {}

-- 2D 基线：引擎里所有 2D/UI 绘制默认假设的状态。
-- 注意 winding 基线是 "ccw"（LÖVE 默认值）；3D pass 需要的绕向由
-- Camera3D:frontFaceWinding() 在 setCanvas 之后动态给出。
local BASELINE = {
    cullMode = "none",
    winding = "ccw",
    blendMode = "alpha",
    blendAlphaMode = "alphamultiply",
}

-- 按 spec 批量设置渲染状态。只设置 spec 里声明的项，未声明的保持现状。
--   spec.shader     : Shader（nil 表示不动）
--   spec.depthMode  : { compareMode, write }，如 { "lequal", true }
--   spec.cullMode   : "back" / "front" / "none"
--   spec.winding    : "cw" / "ccw"
--   spec.blendMode  : { mode, alphaMode }，如 { "alpha", "alphamultiply" }
--   spec.color      : { r, g, b, a }
local function resolve(value, context, pass)
    if type(value) == "function" then return value(context, pass) end
    return value
end

function RenderState.apply(spec, context, pass)
    if not spec then return end
    local shader = resolve(spec.shader, context, pass)
    local depthMode = resolve(spec.depthMode, context, pass)
    local cullMode = resolve(spec.cullMode, context, pass)
    local winding = resolve(spec.winding, context, pass)
    local blendMode = resolve(spec.blendMode, context, pass)
    local color = resolve(spec.color, context, pass)
    if shader then love.graphics.setShader(shader) end
    if depthMode then love.graphics.setDepthMode(depthMode[1], depthMode[2]) end
    if cullMode then love.graphics.setMeshCullMode(cullMode) end
    if winding then love.graphics.setFrontFaceWinding(winding) end
    if blendMode then love.graphics.setBlendMode(blendMode[1], blendMode[2]) end
    if color then love.graphics.setColor(color[1], color[2], color[3], color[4] or 1) end
end

-- 强制还原到 2D 基线并回到 backbuffer。逐项显式还原，绝不遗漏——
-- 这里是"3D 状态泄漏给 UI"问题的唯一出口，宁可多设几项也不做条件判断。
function RenderState.reset()
    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setMeshCullMode(BASELINE.cullMode)
    love.graphics.setFrontFaceWinding(BASELINE.winding)
    love.graphics.setBlendMode(BASELINE.blendMode, BASELINE.blendAlphaMode)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setCanvas()
end

return RenderState
