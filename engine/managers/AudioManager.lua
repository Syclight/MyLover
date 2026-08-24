local ResourceManager = require("engine.managers.ResourceManager")

local AudioManager = {
    currentBGM = nil,
    bgmVolume = 1.0,
    sfxList = {},
    fades = {} -- 用于存储正在淡入淡出的任务
}

local function stopSource(source)
    if type(source) == "userdata" and source.stop then source:stop() end
end

local function releaseSource(source)
    if type(source) == "userdata" and source.release then source:release() end
end

function AudioManager:init()
    -- 设置距离衰减模型，"inverse clamped" 是最自然真实的物理衰减模型
    love.audio.setDistanceModel("inverseclamped")
end

-- ==========================================
-- 基础播放控制
-- ==========================================
-- 播放背景音乐 (支持淡入)
function AudioManager:playBGM(resourceName, fadeDuration)
    -- 用 get()（先 scene 后 global），与 SFX 的查找行为保持一致
    local bgmSource = ResourceManager:get(resourceName)
    if not bgmSource then
        print("【音频警告】AudioManager 找不到 BGM 资源: " .. tostring(resourceName))
        return
    end

    -- 如果当前有音乐，先淡出它
    if self.currentBGM then
        self:stopBGM(fadeDuration)
    end

    self.currentBGM = bgmSource
    self.currentBGM:setLooping(true)

    if fadeDuration and fadeDuration > 0 then
        -- 若与旧 BGM 是同一个 Source（stopBGM 刚注册了它的淡出任务），
        -- fade() 会先取消旧任务；从当前音量续接淡入，避免音量跳变。
        local startVol = bgmSource:isPlaying() and bgmSource:getVolume() or 0
        self.currentBGM:setVolume(startVol)
        self.currentBGM:play()
        self:fade(self.currentBGM, startVol, self.bgmVolume, fadeDuration)
    else
        self:cancelFades(self.currentBGM)
        self.currentBGM:setVolume(self.bgmVolume)
        self.currentBGM:play()
    end
end

-- 停止背景音乐 (支持淡出)
function AudioManager:stopBGM(fadeDuration)
    if not self.currentBGM then return end
    
    local sourceToStop = self.currentBGM
    self.currentBGM = nil -- 立即解除引用，防止冲突
    
    if fadeDuration and fadeDuration > 0 then
        self:fade(sourceToStop, sourceToStop:getVolume(), 0, fadeDuration, function()
            sourceToStop:stop()
        end)
    else
        sourceToStop:stop()
    end
end

-- ==========================================
-- 3D 音效系统
-- ==========================================
-- 播放 3D 音效 (必须是 Mono 单声道音频文件)
function AudioManager:play3DSFX(resourceName, x, y, loop, refDistance)
    -- 注意：音效通常需要 clone()，因为同一个音效可能在不同地方同时响起
    local template = ResourceManager:get(resourceName)
    if not template then return end
    
    local source = template:clone()
    source:setPosition(x, y, 0)
    -- 参考距离：距离多少米时音量开始衰减（比如 1 米）
    source:setReferenceDistance(refDistance or 1.0) 
    source:setLooping(loop or false)
    source:play()
    
    table.insert(self.sfxList, source)
    return source
end

-- -- 播放普通的 2D 音效 (比如 UI 点击)
-- function AudioManager:play2DSFX(resourceName)
--     local template = ResourceManager:get(resourceName)
--     if template then
--         local source = template:clone()
--         -- 将坐标设置为相对于监听器的位置 (0,0,0)，这样就没有 3D 效果了
--         source:setRelative(true)
--         source:setPosition(0, 0, 0)
--         source:play()
--         table.insert(self.sfxList, source)
--     end
-- end

-- 播放普通的 2D 音效 (兼容立体声和单声道)
function AudioManager:play2DSFX(resourceName, pitchVariation, volume)
    local template = ResourceManager:get(resourceName)
    if template then
        local source = template:clone()
        
        -- 【移除】了 setRelative 和 setPosition，防止立体声音频报错
        
        -- 【新增】动态音高微调，打破重复播放时的机械感
        if pitchVariation then
            -- 如果 pitchVariation 是 0.1，则音高会在 0.9 到 1.1 之间随机波动
            local randomPitch = 1.0 + (love.math.random() * 2 - 1) * pitchVariation
            source:setPitch(randomPitch)
        end
        source:setVolume(volume or 1.0)
        source:play()
        table.insert(self.sfxList, source)
    else
        -- 【新增】打破静默失败！如果找不到文件，让控制台大声告诉你
        print("【音频警告】AudioManager 找不到音频资源: " .. tostring(resourceName))
    end
end

-- ==========================================
-- 内部状态机 (淡入淡出与清理)
-- ==========================================
-- 取消某个 Source 上所有进行中的淡入淡出任务（不触发 onComplete）。
-- 同一 Source 同时挂多个 fade 会互相打架：每帧各自 setVolume，音量抖动，
-- 且先完成的 onComplete 可能 stop() 掉正在淡入的音乐。
function AudioManager:cancelFades(source)
    for i = #self.fades, 1, -1 do
        if self.fades[i].source == source then
            table.remove(self.fades, i)
        end
    end
end

function AudioManager:fade(source, startVol, endVol, duration, onComplete)
    self:cancelFades(source) -- 同一 Source 只保留最新任务
    table.insert(self.fades, {
        source = source,
        startVol = startVol,
        endVol = endVol,
        duration = duration,
        timer = 0,
        onComplete = onComplete
    })
end

function AudioManager:update(dt, player)
    -- 1. 更新 3D 监听器 (玩家的耳朵)
    if player then
        love.audio.setPosition(player.x, player.y, 0)
        
        -- 设置耳朵的朝向。前三个参数是前向向量 (Forward)，后三个是头顶向量 (Up)
        local fx = math.cos(player.dir)
        local fy = math.sin(player.dir)
        love.audio.setOrientation(fx, fy, 0,  0, 0, 1)
    end

    -- 2. 处理音量淡入淡出
    for i = #self.fades, 1, -1 do
        local fade = self.fades[i]
        fade.timer = fade.timer + dt
        
        local progress = math.min(1, fade.timer / fade.duration)
        -- 线性插值计算当前音量
        local currentVol = fade.startVol + (fade.endVol - fade.startVol) * progress
        fade.source:setVolume(currentVol)
        
        if progress >= 1 then
            if fade.onComplete then fade.onComplete() end
            table.remove(self.fades, i)
        end
    end

    -- 3. 清理已经播放完毕的 SFX 克隆体，释放内存
    for i = #self.sfxList, 1, -1 do
        if not self.sfxList[i]:isPlaying() then
            releaseSource(self.sfxList[i])
            table.remove(self.sfxList, i)
        end
    end
end

-- ==========================================
-- 场景资源作用域释放前的解引用（由 SceneManager.exitEntry 调用）
-- ==========================================
-- store 是即将被 release 的场景资源表。BGM 引用的是资源表里的原始 Source
-- （不是 clone），release 后再操作它会崩溃，必须在这里停掉并解除引用。
-- SFX 是 clone 出来的独立对象不受影响，但也一并防御性检查。
function AudioManager:onResourcesReleasing(store)
    if not store then return end
    local dying = {}
    for _, resource in pairs(store) do dying[resource] = true end

    if self.currentBGM and dying[self.currentBGM] then
        stopSource(self.currentBGM)
        self.currentBGM = nil
    end
    -- 丢弃引用死亡 Source 的 fade 任务（不触发 onComplete，它可能再碰该 Source）
    for i = #self.fades, 1, -1 do
        if dying[self.fades[i].source] then
            table.remove(self.fades, i)
        end
    end
    -- sfxList 里若混入了原始 Source，只 stop 并移除；release 交给资源作用域，避免二次 release
    for i = #self.sfxList, 1, -1 do
        if dying[self.sfxList[i]] then
            stopSource(self.sfxList[i])
            table.remove(self.sfxList, i)
        end
    end
end

-- ==========================================
-- 场景切换时的强制清理
-- ==========================================
function AudioManager:clear()
    -- 立即停止并清空当前 BGM，不触发淡出
    self:stopBGM()

    for _, fade in ipairs(self.fades or {}) do
        stopSource(fade.source)
    end
    
    -- 清空所有正在进行的淡入淡出任务
    self.fades = {}
    
    -- 停止并释放所有 clone() 出来的短音效，避免循环音效跨场景残留。
    for _, source in ipairs(self.sfxList or {}) do
        stopSource(source)
        releaseSource(source)
    end
    self.sfxList = {}
end

return AudioManager
