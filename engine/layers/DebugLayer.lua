-- 跨场景的调试叠层(性能 / 内存 / LLM 状态 HUD)。
--
-- 它继承 BaseLayer,但不属于任何具体场景:在 main.lua 顶层实例化为单例,
-- 在 SceneManager.draw() 之后绘制,因此天然覆盖一切场景(含暂停菜单)。
-- F3 开关显隐;F4 强制一次 GC;F5 开关"渲染分趟耗时";F7 循环切换帧率上限。
--
-- 显示项与"为什么卡"直接对应:
--   * 帧时间图 + 当前/均值/峰值 ms —— 直观看到卡顿尖峰(对照 60/30fps 预算线)。
--   * Lua GC(collectgarbage)—— 脚本层内存。
--   * GPU 贴图显存 + draw/canvas 切换(love.graphics.getStats)—— 渲染管线开销。
--   * 系统内存占用% / 进程工作集 / 缺页率(SysMem,Windows)—— 判断是否内存压力导致换页。
--   * LLM 服务在途请求数—— 卡顿是否与本地模型推理同步。
--   * 渲染分趟 GPU 耗时(GpuProfiler,F5)—— 每趟画到哪块 canvas、各花多少 ms,
--     定位是哪一趟(主光投 / TAAU / present / FXAA)最贵。
local BaseLayer = require("engine.layers.BaseLayer")
local SysMem = require("engine.utils.SysMem")
local GpuProfiler = require("engine.utils.GpuProfiler")
local FrameLimiter = require("engine.utils.FrameLimiter")
local Timestep = require("engine.utils.Timestep")
local ResourceManager = require("engine.managers.ResourceManager")
local Diagnostics = require("engine.Diagnostics")

local DebugLayer = BaseLayer:extend()

-- ===== 常量 =====
local HISTORY_FRAMES = 120        -- 帧时间环形缓冲长度
local SAMPLE_INTERVAL = 0.25      -- 重采样(内存/GPU)间隔(秒),避免每帧 FFI/系统调用
local GRAPH_MAX_MS = 50.0         -- 帧时间图纵轴上限(毫秒)
local PANEL_X, PANEL_Y = 10, 10
local PANEL_W = 400
local LINE_H = 15
local GRAPH_H = 46
local TOGGLE_KEY = "f3"
local GC_KEY = "f4"
local PROFILE_KEY = "f5" -- 渲染分趟耗时(GpuProfiler）开关
local FPS_CAP_KEY = "f7" -- 循环切换帧率上限(FrameLimiter)
local FPS_CAP_CYCLE = { 0, 30, 60, 120, 144 } -- 0 = 不限制

-- 可选诊断：只有注册了 LLM 服务的游戏才会提供该项。
local function getLLMStats() return Diagnostics.read("llm") end

-- 可选诊断：当前场景主动上报的自定义统计行（字符串数组），如剔除计数。
-- 场景在 enter 里 Diagnostics.register("scene", provider)、exit 里 unregister；
-- 引擎层不认识任何具体场景，边界经由注册表解耦（同 LLM 的做法）。
local function getSceneStats() return Diagnostics.read("scene") end

-- 静态构造(单例用):显式以 DebugLayer 为元表,不依赖调用方用点号还是冒号,
-- 避免 self 丢失导致实例没挂上元表、方法全失效。
function DebugLayer.new()
    local o = setmetatable({}, DebugLayer)
    o.visible = false
    o.font = assert(ResourceManager:getScopeGlobal("font_default_12"),
        "DebugLayer requires font_default_12 from the global manifest")

    -- 当前真正在渲染的 GPU 名(静态,缓存一次)。用来一眼确认是跑在独显还是核显——
    -- 笔记本常把 love.exe 丢给核显跑,导致 RTX 闲置、画面却很卡。
    o.gpuName = "?"
    pcall(function()
        local _, _, vendor, device = love.graphics.getRendererInfo()
        o.gpuName = tostring(device or vendor or "?")
    end)

    -- 帧时间环形缓冲:预分配定长数组 + 写指针。这是性能探针,刻意用可变缓冲
    -- 避免每帧产生垃圾(否则探针自身会污染它要测量的 GC 指标)。
    o.frameTimes = {}
    for i = 1, HISTORY_FRAMES do o.frameTimes[i] = 0 end
    o.frameCursor = 0

    o.sampleTimer = 0
    o.luaMemMB = 0
    o.gpuStats = nil
    o.sysMem = nil
    o.llmStats = nil
    o.sceneStats = nil
    o.resourceStats = nil

    -- 缺页率(每秒)推算
    o.lastPageFaults = nil
    o.lastSampleTime = love.timer.getTime()
    o.pageFaultRate = 0

    return o
end

function DebugLayer:toggle()
    self.visible = not self.visible
end

function DebugLayer:keypressed(key)
    if key == TOGGLE_KEY then
        self:toggle()
        return true
    end
    if key == GC_KEY and self.visible then
        collectgarbage("collect")
        return true
    end
    if key == PROFILE_KEY and self.visible then
        -- 开启会用 glFinish 同步,牺牲并行换取每趟真实 GPU 耗时(本身会略增帧时间)。
        GpuProfiler:setEnabled(not GpuProfiler.enabled)
        return true
    end
    if key == FPS_CAP_KEY and self.visible then
        -- 在 不限/30/60/120/144 之间循环切换帧率上限,方便现场对比限帧效果。
        local current = FrameLimiter:getMaxFPS()
        local index = 1
        for i, v in ipairs(FPS_CAP_CYCLE) do
            if v == current then index = i break end
        end
        FrameLimiter:setMaxFPS(FPS_CAP_CYCLE[(index % #FPS_CAP_CYCLE) + 1])
        return true
    end
    return false
end

function DebugLayer:update(dt)
    -- 帧时间始终采集(开销极小),这样打开面板时立刻有历史曲线。
    self.frameCursor = (self.frameCursor % HISTORY_FRAMES) + 1
    self.frameTimes[self.frameCursor] = dt * 1000.0

    -- 隐藏时不做重采样,零开销。
    if not self.visible then return end

    self.sampleTimer = self.sampleTimer - dt
    if self.sampleTimer > 0 then return end
    self.sampleTimer = SAMPLE_INTERVAL

    self.luaMemMB = collectgarbage("count") / 1024.0
    -- 注意:GPU 统计不在这里采样。getStats() 的 drawcalls/canvasswitches 是"本帧到
    -- 目前为止"的计数、每帧 present() 时清零;update 跑在 draw 之前,此刻本帧还没画东西,
    -- 读到的永远是 0。所以挪到 draw() 顶部、等场景画完再读(见 DebugLayer:draw)。
    self.sysMem = SysMem.query()
    self.llmStats = getLLMStats()
    self.sceneStats = getSceneStats()
    self.resourceStats = ResourceManager:debugStats()

    -- 缺页率
    if self.sysMem and self.sysMem.ok and self.sysMem.pageFaults then
        local now = love.timer.getTime()
        if self.lastPageFaults then
            local elapsed = now - self.lastSampleTime
            if elapsed > 0 then
                self.pageFaultRate = (self.sysMem.pageFaults - self.lastPageFaults) / elapsed
            end
        end
        self.lastPageFaults = self.sysMem.pageFaults
        self.lastSampleTime = now
    end
end

-- 统计帧时间窗口的均值/峰值
function DebugLayer:_frameStats()
    local sum, maxMs = 0, 0
    for i = 1, HISTORY_FRAMES do
        local ms = self.frameTimes[i]
        sum = sum + ms
        if ms > maxMs then maxMs = ms end
    end
    return sum / HISTORY_FRAMES, maxMs
end

function DebugLayer:_drawGraph(x, y, w, h)
    -- 背景
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", x, y, w, h)

    -- 预算参考线:60fps(16.67ms)绿、30fps(33.33ms)黄
    local function budgetLine(ms, r, g, b)
        local ly = y + h - math.min(ms / GRAPH_MAX_MS, 1.0) * h
        love.graphics.setColor(r, g, b, 0.5)
        love.graphics.line(x, ly, x + w, ly)
    end
    budgetLine(16.67, 0.2, 0.9, 0.2)
    budgetLine(33.33, 0.9, 0.9, 0.2)

    -- 帧时间柱:从最旧到最新铺满宽度;超 16.67ms 标红、超 33.33ms 标深红。
    local barW = w / HISTORY_FRAMES
    for i = 1, HISTORY_FRAMES do
        -- 从写指针之后开始读,保证从左到右是时间顺序
        local idx = ((self.frameCursor + i - 1) % HISTORY_FRAMES) + 1
        local ms = self.frameTimes[idx]
        local barH = math.min(ms / GRAPH_MAX_MS, 1.0) * h
        if ms > 33.33 then
            love.graphics.setColor(0.95, 0.25, 0.25, 0.95)
        elseif ms > 16.67 then
            love.graphics.setColor(0.95, 0.65, 0.2, 0.9)
        else
            love.graphics.setColor(0.3, 0.8, 0.4, 0.85)
        end
        local bx = x + (i - 1) * barW
        love.graphics.rectangle("fill", bx, y + h - barH, math.max(barW - 0.5, 0.5), barH)
    end
end

function DebugLayer:draw()
    if not self.visible then return end

    -- GPU 统计必须在这里读:此时本帧的场景已经画完(love.draw 里 SceneManager.draw()
    -- 先于本叠层),getStats() 的 drawcalls/canvasswitches 才反映场景这一帧的真实工作量;
    -- 叠层自身的绘制还没发生,不会被计入。每帧读一次,开销极小。
    self.gpuStats = love.graphics.getStats()

    -- 收集文本行
    local avgMs, maxMs = self:_frameStats()
    local fps = love.timer.getFPS()

    -- 每一行的含义见下方注释。整体诊断思路:
    --   渲染慢 → 看 frame ms / GPU tex；内存压力 → 看 RAM load% / pagefaults；
    --   本地 LLM 抢资源 → 看 LLM 是否 GENERATING 与卡顿是否同步。
    local lines = {}

    -- 【GPU】当前实际渲染用的显卡。若这里显示的是核显(Radeon/Intel/Vega)而你以为在用
    -- 独显(RTX),那就是"跑错 GPU"——卡顿的常见根因,去系统/驱动里把 love.exe 指给独显。
    lines[#lines + 1] = "GPU: " .. (self.gpuName or "?")

    -- 【FPS】每秒实际渲染帧数(love.timer.getFPS,过去 1 秒平均)。越高越流畅。
    -- 【frame avg】最近 120 帧的平均"单帧耗时"(毫秒)。16.7ms≈60fps,33.3ms≈30fps。
    -- 【frame peak】这 120 帧里最慢的一帧——卡顿尖峰看这里(均值正常但 peak 很大=偶发顿挫)。
    -- 【cap】帧率上限(FrameLimiter,F7 切换);off=不限制。
    local cap = FrameLimiter:getMaxFPS()
    lines[#lines + 1] = string.format("FPS %d   frame %.1f ms (avg)  %.1f ms (peak)   cap %s",
        fps, avgMs, maxMs, cap > 0 and tostring(cap) or "off")

    -- 【sim tick】固定步长模拟频率(Hz),与渲染帧率解耦;steps=本帧跑了几次模拟;
    -- alpha=渲染插值因子。渲染掉帧时 tick 仍恒定、steps 自动增多以追平时间。
    lines[#lines + 1] = string.format("sim %d Hz   steps %d   alpha %.2f",
        Timestep:getTickRate(), Timestep.lastSteps, Timestep.alpha)

    -- 【Lua GC】Lua 脚本层占用的堆内存(collectgarbage"count")。只含脚本对象,不含
    -- 贴图/音频等 C 侧资源。持续上涨而不回落=可能有 Lua 内存泄漏。
    lines[#lines + 1] = string.format("Lua GC: %.1f MB", self.luaMemMB)

    if self.gpuStats then
        -- 【GPU tex】当前所有贴图 + canvas 占用的显存(MB)。逼近显卡显存上限会爆显存→卡。
        -- 【draws】本帧的 draw call 次数;数值高=渲染批次多,CPU/GPU 提交开销大。
        -- 【canvas sw】本帧切换渲染目标(canvas)的次数;频繁切 canvas 较昂贵。
        lines[#lines + 1] = string.format("GPU tex: %.1f MB   draws: %d   canvas sw: %d",
            (self.gpuStats.texturememory or 0) / (1024 * 1024),
            self.gpuStats.drawcalls or 0,
            self.gpuStats.canvasswitches or 0)
    end

    if self.resourceStats then
        local scene = self.resourceStats.scene or {}
        local global = self.resourceStats.global or {}
        lines[#lines + 1] = string.format("Resources: scene %d / global %d   tex %d   audio %d",
            scene.total or 0, global.total or 0,
            (scene.images or 0) + (scene.canvases or 0) + (global.images or 0) + (global.canvases or 0),
            (scene.audio or 0) + (global.audio or 0))
    end
    
    if self.sysMem and self.sysMem.ok then
        if self.sysMem.processMB then
            -- 【Game】★ 只统计本游戏进程的内存(这才是"本项目占用")。
            --   ws=工作集(本进程当前占的物理内存,可能含共享 DLL 页);
            --   priv=私有提交(仅属本进程、不共享,≈任务管理器"提交大小",最纯的本项目数字)。
            -- 【pf/s】本进程每秒缺页次数。运行中持续高=内存不足、反复换页=卡顿来源。
            lines[#lines + 1] = string.format("Game RAM: %.0f MB ws / %.0f MB priv   pf %.0f/s",
                self.sysMem.processMB, self.sysMem.privateMB or 0, self.pageFaultRate)
        end
        if self.sysMem.totalMB then
            -- 【RAM used/total】整机物理内存(所有程序),非本项目;仅作环境背景用来
            --   判断系统级内存压力。【load%】≥90% 本行标红=接近满载、可能换页。
            lines[#lines + 1] = string.format("System RAM: %.0f / %.0f MB  (%d%% load)",
                self.sysMem.usedMB or 0, self.sysMem.totalMB or 0, self.sysMem.loadPct or 0)
        end
    else
        -- 非 Windows(或 FFI 不可用):拿不到系统级内存数据,只能显示上面的 Lua/GPU。
        lines[#lines + 1] = "Game RAM: (n/a — non-Windows)"
    end

    if self.llmStats then
        if self.llmStats.started then
            -- 【LLM】大模型管线状态。pending>0 表示有请求正在后台线程里生成
            --   (本地 Ollama 正在吃 GPU/CPU)——此时若画面同步发卡,基本可判定是
            --   本地推理在和渲染抢资源。idle=空闲;GENERATING 这行会高亮橙色。
            local s = self.llmStats.pending > 0
                and string.format("LLM: GENERATING  (pending %d)", self.llmStats.pending)
                or "LLM: idle"
            lines[#lines + 1] = s
        else
            -- 管线尚未 start(当前场景未启用 LLM)。
            lines[#lines + 1] = "LLM: not started"
        end
    end

    -- 【场景诊断】当前场景经 Diagnostics.register("scene", ...) 上报的统计行
    -- (如视锥剔除计数)。0.25s 采样一次,反映的是上一帧的数值,诊断用足够。
    if self.sceneStats then
        lines[#lines + 1] = "-- scene --"
        for _, text in ipairs(self.sceneStats) do
            lines[#lines + 1] = "  " .. tostring(text)
        end
    end

    -- 【渲染分趟耗时】F5 开关。每行 = 一趟绘制画到哪块 canvas + 真实 GPU 毫秒
    -- (经 glFinish 同步测得)。看哪一趟最贵=瓶颈所在;total 是这几趟 GPU 合计。
    -- 开启时因为强制同步,整体帧时间会略高于关闭时,这是测量代价、属正常。
    if GpuProfiler.enabled then
        local passes, n, total = GpuProfiler:getPasses()
        local syncNote = GpuProfiler:hasGpuSync() and "" or " (cpu-only)"
        lines[#lines + 1] = "-- pass GPU time" .. syncNote .. " --"
        if n == 0 then
            lines[#lines + 1] = "  (no instrumented passes)"
        else
            for i = 1, n do
                local p = passes[i]
                lines[#lines + 1] = string.format("  %-9s -> %-11s %5.2f ms", p.name, p.canvas, p.ms)
            end
            lines[#lines + 1] = string.format("  total %.2f ms", total)
        end
    else
        lines[#lines + 1] = "pass GPU time: off (F5)"
    end

    local panelH = LINE_H * #lines + GRAPH_H + 16

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setFont(self.font)

    -- 面板背景
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, panelH)

    -- 文本行
    local ty = PANEL_Y + 6
    for _, text in ipairs(lines) do
        -- LLM 正在生成时高亮(和卡顿对照)
        if text:find("GENERATING") then
            love.graphics.setColor(1.0, 0.55, 0.2, 1.0)
        elseif text:find("load%)") and self.sysMem and (self.sysMem.loadPct or 0) >= 90 then
            love.graphics.setColor(1.0, 0.4, 0.4, 1.0) -- 内存压力高:标红
        else
            love.graphics.setColor(0.9, 0.95, 1.0, 1.0)
        end
        love.graphics.print(text, PANEL_X + 8, ty)
        ty = ty + LINE_H
    end

    -- 帧时间图
    self:_drawGraph(PANEL_X + 8, ty + 2, PANEL_W - 16, GRAPH_H - 6)

    love.graphics.pop()
end

return DebugLayer
