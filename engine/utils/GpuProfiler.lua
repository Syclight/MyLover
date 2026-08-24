-- 通用的"渲染分趟(per-pass / per-canvas)耗时"探针。
--
-- 为什么需要它:OpenGL 是异步的——love.graphics.draw 把命令塞进队列就立刻返回,
-- GPU 之后才真正执行。所以直接用 love.timer 包住一趟绘制,量到的是"CPU 提交时间"
-- (对 shader 密集的趟≈0),完全反映不了真实 GPU 开销。
--
-- 解法:开启 gpuSync 时,在每趟开始/结束各调一次 glFinish()(经 FFI 调 opengl32),
-- 强制 GPU 把队列里的命令全部跑完再读时间。代价是打断 CPU/GPU 并行、整体帧时间变长,
-- 所以这是"profiler 模式":默认 enabled=false,由 DebugLayer 的 F5 开关按需打开。
--
-- 用法(场景的 draw 里):
--   GpuProfiler:beginFrame()
--   GpuProfiler:beginPass("raymarch", "apt_canvas");  ...绘制...;  GpuProfiler:endPass()
--   GpuProfiler:beginPass("taau", "history");         ...绘制...;  GpuProfiler:endPass()
-- DebugLayer 读 GpuProfiler:getPasses() 显示。
local GpuProfiler = {
    enabled = false, -- 总开关(F5)。关闭时所有调用近乎零开销、不记录。
    gpuSync = true,  -- 开启时用 glFinish 量真实 GPU 耗时;关闭则退化为 CPU 提交时间。
    passes = {},     -- 复用的记录池:{ name, canvas, ms },避免每帧产生垃圾
    count = 0,
    total = 0,
    _t0 = 0,
    _name = nil,
    _canvas = nil,
}

-- FFI 懒加载 glFinish(仅 Windows 的 opengl32;失败则 gpuSync 静默退化为 CPU 计时)。
local glFinish = nil
do
    local ok, ffi = pcall(require, "ffi")
    if ok then
        pcall(function()
            ffi.cdef("void glFinish(void);")
            local gl = (ffi.os == "Windows") and ffi.load("opengl32") or ffi.C
            glFinish = function() gl.glFinish() end
        end)
    end
end

-- 每帧绘制开始时调用一次:清空上一帧记录。
function GpuProfiler:beginFrame()
    self.count = 0
    self.total = 0
end

-- 开始一趟。name=趟名;canvasName=该趟渲染到的目标(便于人读"画到哪块 canvas")。
function GpuProfiler:beginPass(name, canvasName)
    if not self.enabled then return end
    -- 先排空此前已排队的 GPU 命令,使本趟计时不含上一趟的尾巴。
    -- 必须先 flushBatch:LÖVE 会把 draw 调用攒在 CPU 侧批次里,直到状态切换才真正
    -- 提交给 GL;glFinish 走 FFI 绕过了 LÖVE,只能等到"已提交"的命令。不 flush 的话
    -- 上一趟的绘制会顺延到下一趟的计时窗口里,所有 pass 的耗时整体错位一格。
    if self.gpuSync and glFinish then
        love.graphics.flushBatch()
        glFinish()
    end
    self._name = name
    self._canvas = canvasName
    self._t0 = love.timer.getTime()
end

-- 结束当前趟:等本趟 GPU 命令真正跑完(glFinish)再记录耗时。
function GpuProfiler:endPass()
    if not self.enabled then return end
    if self.gpuSync and glFinish then
        love.graphics.flushBatch()
        glFinish()
    end
    local ms = (love.timer.getTime() - self._t0) * 1000.0
    self.count = self.count + 1
    local rec = self.passes[self.count]
    if not rec then
        rec = {}
        self.passes[self.count] = rec
    end
    rec.name = self._name
    rec.canvas = self._canvas
    rec.ms = ms
    self.total = self.total + ms
end

-- 供 DebugLayer 读取:返回(记录池, 趟数, 合计毫秒)。
function GpuProfiler:getPasses()
    return self.passes, self.count, self.total
end

function GpuProfiler:setEnabled(value)
    self.enabled = value and true or false
end

-- glFinish 是否可用(不可用时 gpuSync 退化为 CPU 计时,数值仅供参考)。
function GpuProfiler:hasGpuSync()
    return glFinish ~= nil
end

return GpuProfiler
