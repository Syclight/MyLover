-- 固定步长(fixed timestep)模拟器 —— 把"游戏逻辑/模拟"与"渲染帧率"解耦。
--
-- 工业标准做法(参见 Glenn Fiedler《Fix Your Timestep》):
--   每帧把真实帧耗时累加到 accumulator,然后以固定步长 fixedDt 反复 update,
--   直到 accumulator 不足一步;剩下的零头 / fixedDt = alpha(渲染插值因子)。
--
-- 收益:
--   * 渲染掉到 30fps,模拟照样按 tickRate(默认 60Hz)跑 —— 逻辑不随帧率变快变慢;
--   * 模拟确定性,避免"帧率越高物理越快"这类经典 bug;
--   * 模拟频率可独立于渲染(将来 NPC/Agent 社会模拟可用自己的 tick)。
--
-- 防雪崩(spiral of death):
--   单帧 dt 钳到 maxFrameTime;每帧模拟步数封顶 maxSteps,追不上就丢弃积压,
--   否则一次长卡顿(如 15s 场景加载)会触发成百次补帧、越补越卡。
local Timestep = {
    tickRate = 60,        -- 模拟频率(Hz)
    maxFrameTime = 0.25,  -- 单帧 dt 上限(秒):防止长卡顿后累加器爆炸
    maxSteps = 5,         -- 单帧最多模拟步数:超出即丢弃积压,保证渲染能喘气
    accumulator = 0,
    alpha = 0,            -- 渲染插值因子 [0,1):场景可读它在上/当前模拟态间插值
    lastSteps = 0,        -- 上一帧实际跑了几步(调试观察用)
}

function Timestep:setTickRate(hz)
    if hz and hz > 0 then self.tickRate = hz end
end

function Timestep:getTickRate()
    return self.tickRate
end

function Timestep:fixedDt()
    return 1.0 / self.tickRate
end

function Timestep:reset()
    self.accumulator = 0
    self.alpha = 0
    self.lastSteps = 0
end

function Timestep:interpolate(previous, current, alpha)
    return previous + (current - previous) * (alpha or self.alpha)
end

function Timestep:interpolateAngle(previous, current, alpha)
    local delta = (current - previous + math.pi) % (math.pi * 2) - math.pi
    return previous + delta * (alpha or self.alpha)
end

-- 给定真实帧耗时 frameDt,按固定步长调用 stepFn(fixedDt) 若干次,并更新 alpha。
function Timestep:advance(frameDt, stepFn)
    if frameDt > self.maxFrameTime then frameDt = self.maxFrameTime end -- 钳制,防雪崩
    self.accumulator = self.accumulator + frameDt

    local fdt = self:fixedDt()
    local steps = 0
    while self.accumulator >= fdt and steps < self.maxSteps do
        stepFn(fdt)
        self.accumulator = self.accumulator - fdt
        steps = steps + 1
    end

    -- 仍有积压(追不上 maxSteps):丢掉多余,只留不足一步的零头,避免雪崩
    if self.accumulator >= fdt then
        self.accumulator = self.accumulator % fdt
    end

    self.alpha = self.accumulator / fdt
    self.lastSteps = steps
end

return Timestep
