-- 终端审讯会话：把某个被审查市民（persona）+ 当前政府任务包装成一次 LLM 对话，
-- 流式写入终端 transcript。取代第一阶段 NPCDirector，面向"电脑终端"玩法。
local TerminalSession = {}
TerminalSession.__index = TerminalSession

local MAX_HISTORY = 12

local INTERROGATION_FRAME =
    "\n\n【通讯环境】你正通过国家配发的终端与一名政府工作人员通话，对方可能在审查你的忠诚度。" ..
    "请用中文，以日常、简短、口语化的方式回应（1-3 句），符合你的身份与处境，可有潜台词，不要承认自己是 AI。"

function TerminalSession.new(citizen, task, transcript, llm)
    local self = setmetatable({}, TerminalSession)
    self.citizen = citizen
    self.task = task
    self.transcript = transcript
    self.llm = assert(llm, "TerminalSession requires an llm service")
    self.history = {}
    self.busy = false
    return self
end

local function trimHistory(hist)
    while #hist > MAX_HISTORY do table.remove(hist, 1) end
end

function TerminalSession:_append(kind, speaker, text, done)
    local entry = { kind = kind, speaker = speaker, profession = "", text = text or "", done = done == true }
    table.insert(self.transcript, entry)
    return entry
end

-- 系统行（任务简报/结果），立即完成
function TerminalSession:system(text)
    self:_append("system", "系统", text, true)
end

-- 监听员向被审查市民发一句话，市民流式回复
function TerminalSession:send(operatorText)
    if self.busy then return false end
    local citizen = self.citizen
    if not citizen then return false end

    self:_append("operator", "审查员", operatorText, true)

    local messages = { { role = "system", content = (citizen.persona or "") .. INTERROGATION_FRAME } }
    for _, m in ipairs(self.history) do messages[#messages + 1] = m end
    messages[#messages + 1] = { role = "user", content = operatorText }

    local entry = self:_append("npc", citizen.name, "", false)
    entry.profession = citizen.profession or ""
    self.busy = true
    self.sceneStatus = "接收中…"

    self.llm:chat({ messages = messages }, {
        onChunk = function(text)
            entry.text = entry.text .. text
        end,
        onDone = function(full)
            entry.done = true
            self.busy = false
            self.sceneStatus = "已连接"
            self.history[#self.history + 1] = { role = "user", content = operatorText }
            self.history[#self.history + 1] = { role = "assistant", content = full }
            trimHistory(self.history)
        end,
        onError = function(msg)
            entry.text = "[信号中断: " .. tostring(msg) .. "]"
            entry.done = true
            entry.kind = "system"
            self.busy = false
            self.sceneStatus = "信号中断"
        end,
    })
    return true
end

return TerminalSession
