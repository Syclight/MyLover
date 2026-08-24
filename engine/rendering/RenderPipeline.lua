-- 引擎级渲染管线：有序 pass 列表，每个 pass 声明输入/输出 canvas（按名字）。
--
-- 设计要点：
--  * canvas 按"资源名"声明，在 execute 时经 ResourceManager 解析成对象——
--    resetAllCanvases 重建 canvas 后引用会变，逐帧重解析天然吃到 screenSized
--    重建红利，场景的 resize 只需 resetAllCanvases，不用手动重绑引用。
--  * 每个 pass 出口强制 RenderState.reset()：3D 状态绝不泄漏给下一个 pass 或 UI。
--    合成顺序因此被固定：3D/离屏 pass 画进 canvas，execute 结束回到 backbuffer，
--    2D/UI 在 execute 之后直接叠加。
--  * GpuProfiler:beginPass(name, canvasName) 逐 pass 计时（F5 开启时生效）。
--  * 热路径零分配：输出 setCanvas 表、输入解析表都挂在 pass 上复用。
--
-- 用法：
--   local pipeline = RenderPipeline.new("world")
--   pipeline:addPass({
--       name = "gbuffer",
--       output = { "gAlbedo", "gNormal", "gDepth" },  -- MRT；字符串=单目标；nil=backbuffer
--       depth = true,                                  -- 输出附带深度缓冲
--       clear = { 0, 0, 0, 0 },                        -- 进 pass 清屏色（depth=true 时同时清深度）
--       state = { shader = s, depthMode = { "lequal", true }, cullMode = "back" },
--       input = { "someCanvas" },                      -- 可选；解析结果传给 draw
--       draw = function(context, inputs, pass) ... end,
--   })
--   pipeline:execute(context)  -- context 原样传给每个 draw
local ResourceManager = require("engine.managers.ResourceManager")
local RenderState = require("engine.rendering.RenderState")
local GpuProfiler = require("engine.utils.GpuProfiler")

local RenderPipeline = {}
RenderPipeline.__index = RenderPipeline

function RenderPipeline.new(name)
    local self = setmetatable({}, RenderPipeline)
    self.name = name or "pipeline"
    self.passes = {}
    return self
end

local function normalizeNames(value)
    if value == nil then return nil end
    if type(value) == "string" then return { value } end
    assert(type(value) == "table", "canvas declaration must be a name or a list of names")
    return value
end

function RenderPipeline:addPass(def)
    assert(type(def) == "table", "addPass expects a pass definition table")
    assert(type(def.name) == "string" and def.name ~= "", "pass needs a name")
    assert(type(def.draw) == "function", "pass '" .. def.name .. "' needs a draw function")

    local pass = {
        name = def.name,
        outputNames = normalizeNames(def.output),
        inputNames = normalizeNames(def.input),
        depth = def.depth or false,
        clear = def.clear,
        state = def.state,
        draw = def.draw,
        enabled = def.enabled ~= false,
        -- 复用的解析缓冲（execute 每帧重填，不产生垃圾）
        _target = def.output and {} or nil,
        _inputs = def.input and {} or nil,
        -- 供 GpuProfiler 显示的目标标签
        _label = def.output and table.concat(normalizeNames(def.output), "+") or "backbuffer",
    }
    self.passes[#self.passes + 1] = pass
    return self
end

function RenderPipeline:getPass(name)
    for _, pass in ipairs(self.passes) do
        if pass.name == name then return pass end
    end
    return nil
end

function RenderPipeline:setEnabled(name, enabled)
    local pass = assert(self:getPass(name), "unknown pass: " .. tostring(name))
    pass.enabled = enabled and true or false
end

local function resolveCanvas(self, pass, name)
    local canvas = ResourceManager:get(name)
    if not canvas then
        error(("RenderPipeline '%s' pass '%s': canvas '%s' not found in ResourceManager")
            :format(self.name, pass.name, name))
    end
    return canvas
end

local function bindTarget(self, pass)
    if not pass.outputNames then
        love.graphics.setCanvas()
        pass.viewportWidth, pass.viewportHeight = love.graphics.getDimensions()
        return
    end
    local target = pass._target
    for i, name in ipairs(pass.outputNames) do
        target[i] = resolveCanvas(self, pass, name)
    end
    target.depth = pass.depth and true or nil
    love.graphics.setCanvas(target)
    pass.viewportWidth, pass.viewportHeight = target[1]:getDimensions()
end

local function clearTarget(pass)
    local clear = pass.clear
    if clear == nil then return end
    if clear == true then
        love.graphics.clear(0, 0, 0, 0, false, pass.depth and true or false)
    else
        -- clear 深度与颜色一次完成（第 5 参是 stencil，第 6 参是 depth）
        love.graphics.clear(clear[1], clear[2], clear[3], clear[4] or 1,
            false, pass.depth and true or false)
    end
end

-- 执行整条管线。context 原样传给每个 pass 的 draw(context, inputs, pass)。
-- 返回后保证：canvas 回到 backbuffer，渲染状态回到 2D 基线（RenderState.reset）。
function RenderPipeline:execute(context)
    for _, pass in ipairs(self.passes) do
        if pass.enabled then
            GpuProfiler:beginPass(pass.name, pass._label)

            bindTarget(self, pass)
            clearTarget(pass)
            RenderState.apply(pass.state, context, pass)

            local inputs = pass._inputs
            if inputs then
                for i, name in ipairs(pass.inputNames) do
                    inputs[i] = resolveCanvas(self, pass, name)
                end
            end
            pass.draw(context, inputs, pass)

            -- 出 pass 强制还原：状态泄漏在这里被拦截，与 draw 内部做了什么无关
            RenderState.reset()
            GpuProfiler:endPass()
        end
    end
end

return RenderPipeline
