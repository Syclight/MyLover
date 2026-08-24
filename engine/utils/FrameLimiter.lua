-- 帧率 / 每帧最短 tick 时间限制器。配合自定义 love.run 使用(见 main.lua)。
--
--   maxFPS = 0  → 不限制(由 vsync / 显卡决定上限)
--   maxFPS > 0  → 把每帧最短耗时钳到 1/maxFPS 秒,多出来的时间用 love.timer.sleep
--                 让出 CPU(不忙等自旋——自旋会空转烧 CPU、加剧笔记本发热降频)。
--
-- 注意:这是"下限耗时 / 上限帧率"。它只能让帧变慢(限速),不能让帧变快;
-- 真实帧率仍受 vsync 与渲染本身耗时影响。若要真正不限速,记得同时关掉 vsync。
local FrameLimiter = {
    maxFPS = 0, -- 0 = 不限制
}

function FrameLimiter:setMaxFPS(fps)
    self.maxFPS = (fps and fps > 0) and fps or 0
end

function FrameLimiter:getMaxFPS()
    return self.maxFPS
end

function FrameLimiter:isLimited()
    return self.maxFPS > 0
end

-- 每帧目标最短耗时(秒);不限制时返回 nil。
function FrameLimiter:targetFrameTime()
    if self.maxFPS > 0 then return 1.0 / self.maxFPS end
    return nil
end

-- 在一帧末尾调用:距 frameStart 还不够目标耗时,就 sleep 补足。
-- 用 sleep 而非忙等:精度约 ~1ms(够游戏限帧用),且不空转 CPU。
function FrameLimiter:wait(frameStart)
    local target = self:targetFrameTime()
    if not target then return end
    local remaining = target - (love.timer.getTime() - frameStart)
    if remaining > 0 then
        love.timer.sleep(remaining)
    end
end

return FrameLimiter
