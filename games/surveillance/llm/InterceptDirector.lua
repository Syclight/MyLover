local GameClock = require("games.surveillance.gameplay.GameClock")

local InterceptDirector = {}
InterceptDirector.__index = InterceptDirector

local MAX_TRANSCRIPT = 80
local NOISE = {
    "短促载波掠过，没有可辨识的语音。",
    "只收到餐具碰撞和远处广播声。",
    "信号里有几秒呼吸声，随后归于静默。",
    "一段串频覆盖了频道，内容无法辨认。",
    "线路接通又立刻断开，未形成有效通话。",
}

local function clearInPlace(t)
    for i = #t, 1, -1 do t[i] = nil end
end

local function inWindow(minute, window)
    if window.start <= window.finish then
        return minute >= window.start and minute < window.finish
    end
    return minute >= window.start or minute < window.finish
end

function InterceptDirector.new(transcript, llm, clock, evidenceLog, options)
    if evidenceLog and evidenceLog.random then
        options = evidenceLog
        evidenceLog = nil
    end
    options = options or {}
    local self = setmetatable({}, InterceptDirector)
    self.transcript = transcript
    self.llm = assert(llm, "InterceptDirector requires an llm service")
    self.clock = assert(clock, "InterceptDirector requires a game clock")
    self.evidenceLog = evidenceLog
    self.random = options.random or love.math.random
    self.state = "idle" -- idle | waiting | conversation | cooldown
    self.activeStatus = "待机"
    self.busy = false
    self.activeId = nil
    self.channel = nil
    self.nextActionAt = math.huge
    self.turnIndex = 0
    self.callLength = 0
    self.lastLine = nil
    self.topic = nil
    self.informationLevel = nil
    self.activity = nil
    return self
end

function InterceptDirector.isWithinWindow(minute, window)
    return inWindow(minute, window)
end

function InterceptDirector:_rand(a, b)
    if a == nil then return self.random() end
    if b == nil then return self.random(a) end
    return self.random(a, b)
end

function InterceptDirector:_append(entry)
    table.insert(self.transcript, entry)
    while #self.transcript > MAX_TRANSCRIPT do table.remove(self.transcript, 1) end
    return entry
end

function InterceptDirector:_stamp(text)
    return GameClock.format(self.clock) .. "  " .. text
end

function InterceptDirector:_activityAt(minute)
    if not self.channel then return nil end
    for _, window in ipairs(self.channel.windows or {}) do
        if inWindow(minute, window) then return window end
    end
    return nil
end

function InterceptDirector:monitor(channel)
    self:stop()
    clearInPlace(self.transcript)
    self.channel = channel
    self.state = "waiting"
    self.busy = false
    self.nextActionAt = self.clock.absoluteMinutes + 1
    self.activeStatus = "扫描中"
    self:_append({
        kind = "system", speaker = "截获", done = true,
        text = self:_stamp("── 接入频道 " .. (channel.freq or "") .. "："
            .. channel.a.name .. " ⇄ " .. channel.b.name .. " ──"),
    })
end

function InterceptDirector:stop()
    if self.activeId then self.llm:cancel(self.activeId) end
    self.activeId = nil
    self.state = "idle"
    self.busy = false
    self.channel = nil
    self.nextActionAt = math.huge
    self.activeStatus = "已停止"
end

-- 空格：通话中切断；静默或冷却时立即重新扫描。
function InterceptDirector:newTopic()
    if self.state == "idle" then return end
    if self.state == "conversation" or self.busy then
        if self.activeId then self.llm:cancel(self.activeId) end
        self.activeId = nil
        self.busy = false
        self:_finishCall("操作员手动中断")
        return
    end
    self.state = "waiting"
    self.nextActionAt = self.clock.absoluteMinutes
    self.activeStatus = "扫描中"
    self:_append({ kind = "system", speaker = "截获", done = true, text = self:_stamp("操作员请求立即扫描。") })
end

function InterceptDirector:tick(_dt)
    if self.state == "idle" or self.busy or self.clock.absoluteMinutes < self.nextActionAt then return end
    if self.state == "conversation" then
        self:_nextTurn()
    else
        self:_scan()
    end
end

function InterceptDirector:_scan()
    local window = self:_activityAt(GameClock.minuteOfDay(self.clock))
    if not window then
        self.state = "waiting"
        self.activeStatus = "频道静默"
        self.nextActionAt = self.clock.absoluteMinutes + self:_rand(8, 16)
        self:_append({ kind = "system", speaker = "截获", done = true,
            text = self:_stamp("[载波静默] 当前不在双方的惯常联络时段。") })
        return
    end

    local callChance = self.channel.callChance or 0.58
    if self:_rand() >= callChance then
        self.state = "waiting"
        self.activeStatus = "无有效信息"
        self.nextActionAt = self.clock.absoluteMinutes + self:_rand(5, 12)
        self:_append({ kind = "system", speaker = "截获", done = true,
            text = self:_stamp("[日常背景] " .. NOISE[self:_rand(#NOISE)]) })
        return
    end

    self.activity = window.activity
    self.informationLevel = self:_rand() < (self.channel.clueChance or 0.18) and "clue" or "mundane"
    local pool = self.informationLevel == "clue" and self.channel.clueTopics or self.channel.mundaneTopics
    self.topic = pool[self:_rand(#pool)]
    self.callLength = self:_rand(2, 4)
    self.turnIndex = 0
    self.lastLine = nil
    self.state = "conversation"
    -- 不在 HUD 上替玩家标注“关键线索”，是否重要应由玩家从内容中判断。
    self.activeStatus = "通讯中 · 信号稳定"
    self:_append({ kind = "system", speaker = "截获", done = true,
        text = self:_stamp("── 捕获私人通讯 · " .. window.activity .. " ──") })
    self:_nextTurn()
end

function InterceptDirector:_finishCall(reason)
    self:_append({ kind = "system", speaker = "截获", done = true,
        text = self:_stamp("── 通讯结束" .. (reason and " · " .. reason or "") .. " ──") })
    self.state = "cooldown"
    self.busy = false
    self.activeId = nil
    self.activeStatus = "频道静默"
    self.nextActionAt = self.clock.absoluteMinutes + self:_rand(18, 40)
    self.lastLine = nil
end

function InterceptDirector:_nextTurn()
    if not self.channel then return end
    local speaker = self.turnIndex % 2 == 0 and self.channel.a or self.channel.b
    local other = self.turnIndex % 2 == 0 and self.channel.b or self.channel.a
    local levelRule
    if self.informationLevel == "clue" then
        levelRule = "这次通话含有一条值得监听者留意的异常信息。自然地泄露一点线索，但不要解释全貌或直接自曝秘密。"
    else
        levelRule = "这次只是普通日常联络。内容可以琐碎、重复甚至对监听者毫无用处；不要主动透露重大秘密。"
    end

    local frame = (speaker.persona or "")
        .. "\n\n【本次私人通讯】当前日期时间：" .. GameClock.formatDate(self.clock) .. " " .. GameClock.format(self.clock)
        .. "。日常情境：" .. tostring(self.activity) .. "。话题：" .. tostring(self.topic) .. "。"
        .. levelRule
        .. " 使用中文口语，只说 1-2 句，不写动作、旁白、姓名前缀，也不要承认自己是 AI。"
    local userMsg
    if self.lastLine then
        userMsg = other.name .. "刚才说：『" .. self.lastLine .. "』。请顺着当前日常情境简短回应。"
    else
        userMsg = "你正在和" .. other.name .. "进行一次很短的私人通讯，请自然地从『" .. self.topic .. "』开口。"
    end

    local entry = self:_append({
        kind = "npc", speaker = speaker.name, profession = speaker.profession or "",
        text = "", done = false, informationLevel = self.informationLevel,
    })
    self.busy = true
    local requestId = self.llm:chat({ messages = {
        { role = "system", content = frame },
        { role = "user", content = userMsg },
    } }, {
        onChunk = function(text) entry.text = entry.text .. text end,
        onDone = function(full)
            entry.done = true
            self.busy = false
            self.activeId = nil
            self.lastLine = full
            if self.informationLevel == "clue" and self.evidenceLog then
                local EvidenceLog = require("games.surveillance.gameplay.EvidenceLog")
                EvidenceLog.add(self.evidenceLog, self.clock, {
                    channelId = self.channel.id,
                    frequency = self.channel.freq,
                    speaker = speaker.name,
                    profession = speaker.profession or "",
                    counterpart = other.name,
                    activity = self.activity,
                    topic = self.topic,
                    quote = full,
                })
            end
            self.turnIndex = self.turnIndex + 1
            if self.turnIndex >= self.callLength then
                self:_finishCall()
            else
                self.activeStatus = "通讯中 · 信号稳定"
                self.nextActionAt = self.clock.absoluteMinutes + self:_rand(1, 3)
            end
        end,
        onError = function(msg)
            entry.text = "[信号中断: " .. tostring(msg) .. "]"
            entry.done = true
            entry.kind = "system"
            self.busy = false
            self.activeId = nil
            self:_finishCall("信号丢失")
        end,
    })
    -- 兼容测试桩或未来可能同步完成的服务，避免回调清空后又留下陈旧 id。
    if self.busy then self.activeId = requestId end
end

return InterceptDirector
