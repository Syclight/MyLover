-- 政府任务终端 UI（terminal 模式），两个视图（TAB 切换）：
--   审讯 interrogate —— 任务简报 + 与目标市民对话 + F1/F2 裁决
--   监听 intercept    —— 先选频道(list)，再监听该频道两位市民的 LLM 对话(monitor)
-- 离开监听页面（Backspace/Esc/TAB/离开终端）会停止该会话并取消在途请求。
-- 日志支持滚轮 + 滚动条翻看历史。
local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")
local ChatLog = require("engine.ui.components.ChatLog")
local TextInput = require("engine.ui.components.TextInput")
local UIContext = require("engine.ui.UIContext")
local Button = require("engine.ui.components.Button")
local TerminalSession = require("games.surveillance.llm.TerminalSession")
local InterceptDirector = require("games.surveillance.llm.InterceptDirector")
local ComputerOS = require("games.surveillance.computer.ComputerOS")
local EvidenceLog = require("games.surveillance.gameplay.EvidenceLog")
local GameClock = require("games.surveillance.gameplay.GameClock")
local utf8 = require("utf8")

local citizens = require("games.surveillance.data.residents")
local tasks = require("games.surveillance.data.tasks")
local channelDefs = require("games.surveillance.data.channels")

local TerminalLayer = BaseLayer:extend()

local SCROLL_STEP = 54

local function clamp(v, a, b) return math.max(a, math.min(v, b)) end

function TerminalLayer:new(sceneState, llm)
    local o = BaseLayer.new(self)
    o.sceneState = sceneState
    o.llm = assert(llm, "TerminalLayer requires the llm service")
    return o
end

function TerminalLayer:enter()
    self.font = ResourceManager:get("font_NotoSerifSC-Regular_14")
    self.titleFont = ResourceManager:get("font_NotoSerifSC-Regular_18")

    love.math.setRandomSeed(os.time())

    self.citizenById = {}
    for _, c in ipairs(citizens) do self.citizenById[c.id] = c end

    -- 解析频道（id 转为市民对象）
    self.channels = {}
    for _, ch in ipairs(channelDefs) do
        local a, b = self.citizenById[ch.a], self.citizenById[ch.b]
        if a and b then
            local resolved = {}
            for key, value in pairs(ch) do resolved[key] = value end
            resolved.a, resolved.b = a, b
            self.channels[#self.channels + 1] = resolved
        end
    end

    local terminal = self.sceneState.terminal
    terminal.transcript = terminal.transcript or {}
    terminal.interceptTranscript = terminal.interceptTranscript or {}
    terminal.input = terminal.input or ""
    terminal.status = "离线"
    terminal.taskIndex = terminal.taskIndex or 1
    terminal.verdicts = terminal.verdicts or {}
    terminal.view = terminal.view or "interrogate"
    terminal.interceptMode = terminal.interceptMode or "list"
    terminal.interceptIndex = terminal.interceptIndex or 1
    terminal.os = terminal.os or ComputerOS.new()
    terminal.notes = terminal.notes or ""
    terminal.archiveIndex = terminal.archiveIndex or 1

    self.intercept = InterceptDirector.new(terminal.interceptTranscript, self.llm,
        self.sceneState.clock, self.sceneState.evidence)
    self.scrollInterrogate = { scroll = 0, follow = true }
    self.scrollIntercept = { scroll = 0, follow = true }

    self:loadTask(terminal.taskIndex)
end

function TerminalLayer:openOS()
    ComputerOS.beginSession(self.sceneState.terminal.os)
end

-- ===== 审讯任务 =====
function TerminalLayer:loadTask(index)
    local terminal = self.sceneState.terminal
    terminal.taskIndex = index
    self.scrollInterrogate.follow = true
    local task = tasks[index]
    if not task then
        self.session = nil
        terminal.status = "全部完成"
        TerminalSession.new(nil, nil, terminal.transcript, self.llm):system("【系统】全部审查任务完毕。无待处理目标。")
        return
    end
    local citizen = self.citizenById[task.targetCitizenId]
    self.session = TerminalSession.new(citizen, task, terminal.transcript, self.llm)
    terminal.status = "已连接"
    self.session:system(
        "—— 国家安全部 审查终端 ——\n任务 " .. index .. "/" .. #tasks .. "：" .. task.title ..
        "\n" .. task.briefing ..
        "\n（输入问题后回车开始审讯；F1=忠诚  F2=嫌疑 提交裁决；TAB=切换监听）"
    )
end

function TerminalLayer:advanceTask()
    self:loadTask(self.sceneState.terminal.taskIndex + 1)
    self.sceneState.terminal.input = ""
end

function TerminalLayer:submitVerdict(loyal)
    if not self.session or not self.session.task or self.session.busy then return end
    local label = loyal and "忠诚" or "嫌疑"
    self.sceneState.terminal.verdicts[self.session.task.id] = label
    self.session:system("【裁决已提交】对「" .. (self.session.citizen and self.session.citizen.name or "目标") .. "」判定：" .. label)
    self:advanceTask()
end

-- ===== 视图 / 频道切换 =====
function TerminalLayer:toggleView()
    local t = self.sceneState.terminal
    if t.view == "intercept" then
        if t.interceptMode == "monitor" then self:exitMonitor() end
        t.view = "interrogate"
    else
        t.view = "intercept"
    end
end

function TerminalLayer:enterChannel(i)
    local ch = self.channels[i]
    if not ch then return end
    self.sceneState.terminal.interceptMode = "monitor"
    self.scrollIntercept.scroll = 0
    self.scrollIntercept.follow = true
    self.scrollIntercept.prevH = nil
    self.intercept:monitor(ch) -- 开始监听该频道
end

function TerminalLayer:exitMonitor()
    self.intercept:stop() -- 停止并取消在途请求
    self.sceneState.terminal.interceptMode = "list"
end

-- 供 Scene 处理 Esc：监听中时 Esc 返回频道列表（并停止），返回 true 表示已消费
function TerminalLayer:handleEscape()
    local t = self.sceneState.terminal
    if t.os.activeApp == "surveillance" and t.view == "intercept" and t.interceptMode == "monitor" then
        self:exitMonitor()
        return true
    end
    if ComputerOS.backToDesktop(t.os) then return true end
    return false
end

-- 离开终端时由 Scene 调用：停止一切监听交互
function TerminalLayer:stopAll()
    if self.intercept then self.intercept:stop() end
    local t = self.sceneState.terminal
    if t and t.view == "intercept" then t.interceptMode = "list" end
end

-- ===== 输入 =====
-- 审查员输入框的屏幕矩形（与 draw 中 TextInput 位置一致），供输入法定位候选窗
function TerminalLayer:_inputRect()
    local w, h = love.graphics.getDimensions()
    local margin = 40
    return margin, h - 116, w - margin * 2, self.font:getHeight() + 16
end

-- 仅在"终端模式 + 审讯视图"启用文本输入并把输入法候选窗定位到输入框；
-- 其余情况（行走 / 监听）关闭文本输入，避免输入法吞掉 WASD/方向键等操作。
function TerminalLayer:_applyTextInput(typing)
    if typing then
        local x, y, w, h = self:_inputRect()
        love.keyboard.setTextInput(true, x, y, w, h)
        self._imeOn = true
    elseif self._imeOn ~= false then -- nil(初次) 或 true 都需要明确关闭
        love.keyboard.setTextInput(false)
        self._imeOn = false
        self.sceneState.terminal.composition = nil
    end
end

function TerminalLayer:update(dt)
    local t = self.sceneState.terminal
    local apt = self.sceneState.apartment
    if apt and apt.mode == "terminal" then ComputerOS.update(t.os, dt) end

    local app = t.os.activeApp
    local typing = apt ~= nil and apt.mode == "terminal" and t.os.bootTimer <= 0
        and (app == "notes" or (app == "surveillance" and t.view == "interrogate"))
    self:_applyTextInput(typing)

    if app == "surveillance" and t.view == "intercept" and t.interceptMode == "monitor" then
        self.intercept:tick(dt)
        t.status = self.intercept.activeStatus or "监听中"
    elseif t.view == "interrogate" and self.session and self.session.sceneStatus then
        t.status = self.session.sceneStatus
    end
end

function TerminalLayer:textinput(ch)
    local terminal = self.sceneState.terminal
    if terminal.os.activeApp == "notes" then
        if #terminal.notes < 4000 then terminal.notes = terminal.notes .. ch end
        return
    end
    if terminal.os.activeApp ~= "surveillance" or terminal.view ~= "interrogate" then return end
    self.sceneState.terminal.input = (self.sceneState.terminal.input or "") .. ch
    self.sceneState.terminal.composition = nil -- 已上屏，清掉合成串
end

-- 输入法合成串（拼字尚未上屏）：实时显示在输入框里
function TerminalLayer:textedited(text)
    if self.sceneState.terminal.os.activeApp ~= "surveillance"
        or self.sceneState.terminal.view ~= "interrogate" then return end
    self.sceneState.terminal.composition = text or ""
end

function TerminalLayer:keypressed(key)
    local t = self.sceneState.terminal
    if t.os.bootTimer > 0 then return end
    local app = t.os.activeApp
    if app == "desktop" then
        ComputerOS.keypressedDesktop(t.os, key)
        return
    elseif app == "archives" then
        if key == "up" then t.archiveIndex = clamp(t.archiveIndex - 1, 1, #citizens)
        elseif key == "down" then t.archiveIndex = clamp(t.archiveIndex + 1, 1, #citizens) end
        return
    elseif app == "evidence" then
        if key == "up" then EvidenceLog.moveSelection(self.sceneState.evidence, -1)
        elseif key == "down" then EvidenceLog.moveSelection(self.sceneState.evidence, 1)
        elseif key == "return" or key == "kpenter" then
            EvidenceLog.markReviewed(self.sceneState.evidence)
        end
        return
    elseif app == "notes" then
        if key == "backspace" then
            local byteoffset = utf8.offset(t.notes, -1)
            if byteoffset then t.notes = t.notes:sub(1, byteoffset - 1) else t.notes = "" end
        elseif key == "return" or key == "kpenter" then
            if #t.notes < 4000 then t.notes = t.notes .. "\n" end
        end
        return
    elseif app == "system" then
        return
    end

    if key == "tab" then
        self:toggleView()
        return
    end

    if t.view == "intercept" then
        if t.interceptMode == "list" then
            if key == "up" then
                t.interceptIndex = clamp(t.interceptIndex - 1, 1, #self.channels)
            elseif key == "down" then
                t.interceptIndex = clamp(t.interceptIndex + 1, 1, #self.channels)
            elseif key == "return" or key == "kpenter" then
                self:enterChannel(t.interceptIndex)
            end
        else
            if key == "space" then
                self.intercept:newTopic()
            elseif key == "backspace" then
                self:exitMonitor()
            end
        end
        return
    end

    -- 审讯视图
    if key == "backspace" then
        local sstr = t.input or ""
        local byteoffset = utf8.offset(sstr, -1)
        if byteoffset then t.input = sstr:sub(1, byteoffset - 1) else t.input = "" end
    elseif key == "return" or key == "kpenter" then
        local text = (t.input or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" and self.session and self.session.citizen then
            if self.session:send(text) then t.input = "" end
        end
    elseif key == "f1" then
        self:submitVerdict(true)
    elseif key == "f2" then
        self:submitVerdict(false)
    end
end

function TerminalLayer:wheelmoved(dx, dy)
    local t = self.sceneState.terminal
    if t.os.activeApp == "archives" and dy ~= 0 then
        t.archiveIndex = clamp(t.archiveIndex + (dy < 0 and 1 or -1), 1, #citizens)
        return
    elseif t.os.activeApp == "evidence" and dy ~= 0 then
        EvidenceLog.moveSelection(self.sceneState.evidence, dy < 0 and 1 or -1)
        return
    elseif t.os.activeApp ~= "surveillance" then
        return
    end
    local st
    if t.view == "intercept" and t.interceptMode == "monitor" then
        st = self.scrollIntercept
    elseif t.view == "interrogate" then
        st = self.scrollInterrogate
    else
        return
    end
    if dy > 0 then
        st.follow = false
        st.scroll = math.min(st.scroll + SCROLL_STEP, st.maxScroll or 0)
    elseif dy < 0 then
        st.scroll = math.max(st.scroll - SCROLL_STEP, 0)
        if st.scroll <= 0 then st.follow = true end
    end
end

-- ===== 绘制 =====
local function drawHeader(self, title, subtitle, status, w, margin)
    love.graphics.setColor(0.2, 0.5, 0.3, 0.5)
    love.graphics.rectangle("fill", margin, 24, w - margin * 2, 64, 6)
    love.graphics.setColor(0.5, 1, 0.7, 1)
    love.graphics.setFont(self.titleFont)
    love.graphics.print("▍ " .. title, margin + 14, 32)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.8, 1, 0.9, 0.9)
    if subtitle then
        love.graphics.printf(subtitle, margin + 14, 58, w - margin * 2 - 180, "left")
    end
    local connected = (status == "已连接") or (status and (
        status:find("扫描", 1, true) or status:find("通讯", 1, true) or status:find("静默", 1, true)))
    love.graphics.setColor(connected and { 0.3, 1, 0.4 } or { 1, 0.4, 0.3 })
    love.graphics.circle("fill", w - margin - 12, 36, 6)
    love.graphics.setColor(0.8, 1, 0.9, 0.9)
    love.graphics.printf(status or "", w - margin - 160, 30, 140, "right")
end

-- 绘制日志并维护 st 的滚动状态（贴底跟随 / 翻看历史时随新内容补偿）
function TerminalLayer:_scrollLog(st, transcript, x, y, w, h)
    local info = ChatLog.draw(self.font, transcript, x, y, w, h, st.scroll)
    local grew = info.contentH - (st.prevH or info.contentH)
    if st.follow then
        st.scroll = 0
    elseif grew > 0 then
        st.scroll = math.min(st.scroll + grew, info.maxScroll)
    end
    st.scroll = clamp(st.scroll, 0, info.maxScroll)
    st.prevH = info.contentH
    st.maxScroll = info.maxScroll
end

local function hint(self, text, x, h)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.7, 0.9, 0.8, 0.5)
    love.graphics.print(text, x, h - 70)
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawTaskbar(self, terminal, w, h)
    love.graphics.setColor(0.025, 0.045, 0.055, 0.98)
    love.graphics.rectangle("fill", 0, h - 42, w, 42)
    if Button.new("os_desktop", "◈ 桌面", 8, h - 36, 112, 30, "gray") then
        if self.intercept then self.intercept:stop() end
        terminal.os.activeApp = "desktop"
    end
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.72, 0.88, 0.84, 0.9)
    local clock = self.sceneState.clock
    love.graphics.printf(GameClock.formatDate(clock) .. "  " .. GameClock.format(clock),
        w - 370, h - 31, 350, "right")
end

local function drawBoot(self, terminal, w, h)
    love.graphics.setColor(0.008, 0.018, 0.022, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.42, 1.0, 0.72, 1)
    love.graphics.printf("A 城公寓终端系统", 0, h * 0.42, w, "center")
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.48, 0.70, 0.62, 0.9)
    love.graphics.printf("正在验证住户身份" .. string.rep(".", math.floor(terminal.os.bootTimer * 4) % 4),
        0, h * 0.50, w, "center")
end

local function drawDesktop(self, terminal, w, h)
    love.graphics.setColor(0.025, 0.11, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(0.06, 0.24, 0.20, 0.65)
    love.graphics.circle("fill", w * 0.78, h * 0.25, math.min(w, h) * 0.34)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.70, 0.94, 0.84, 0.9)
    love.graphics.print("公寓终端桌面", 30, 24)
    for index, app in ipairs(ComputerOS.apps) do
        local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
        local x, y = 70 + col * 250, 100 + row * 145
        local selected = terminal.os.selected == index
        local theme = selected and "primary" or "gray"
        local subtitle = app.subtitle
        if app.id == "evidence" then
            local unread = EvidenceLog.unreviewedCount(self.sceneState.evidence)
            if unread > 0 then subtitle = subtitle .. " · " .. tostring(unread) .. " 条未读" end
        end
        if Button.new("os_app_" .. app.id, app.label .. "\n" .. subtitle, x, y, 210, 105, theme) then
            terminal.os.selected = index
            ComputerOS.openSelected(terminal.os)
        end
        love.graphics.setFont(self.font)
        love.graphics.setColor(0.75, 0.90, 0.84, 0.65)
        love.graphics.print("[" .. index .. "]", x + 8, y + 8)
    end
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.72, 0.88, 0.82, 0.7)
    love.graphics.print("方向键/Tab 选择 · Enter 打开 · Esc 退出电脑", 30, h - 72)
    drawTaskbar(self, terminal, w, h)
end

local function drawArchives(self, terminal, w, h)
    love.graphics.setColor(0.055, 0.065, 0.060, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.82, 0.86, 0.72, 1)
    love.graphics.print("公民档案数据库", 28, 22)
    for index, citizen in ipairs(citizens) do
        local y = 72 + (index - 1) * 54
        if Button.new("archive_" .. citizen.id, citizen.name .. " · " .. citizen.profession,
            28, y, 300, 44, terminal.archiveIndex == index and "primary" or "gray") then
            terminal.archiveIndex = index
        end
    end
    local citizen = citizens[terminal.archiveIndex]
    local x = 370
    love.graphics.setColor(0.10, 0.12, 0.105, 0.95)
    love.graphics.rectangle("fill", x, 72, w - x - 30, h - 142, 7)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.92, 0.86, 0.66, 1)
    love.graphics.print(citizen.name, x + 24, 96)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.80, 0.84, 0.76, 0.9)
    love.graphics.print("职业：" .. citizen.profession, x + 24, 142)
    love.graphics.print("登记频率：" .. citizen.channel .. " MHz", x + 24, 174)
    local verdict = "未审查"
    for _, task in ipairs(tasks) do
        if task.targetCitizenId == citizen.id then verdict = terminal.verdicts[task.id] or "待审查" break end
    end
    love.graphics.print("审查状态：" .. verdict, x + 24, 206)
    love.graphics.setColor(0.62, 0.72, 0.66, 0.75)
    local profile = citizen.profile or {}
    love.graphics.setColor(0.80, 0.82, 0.72, 0.9)
    love.graphics.printf(profile.biography or "暂无生平记录。", x + 24, 252, w - x - 78, "left")
    love.graphics.setColor(0.62, 0.72, 0.66, 0.75)
    love.graphics.printf("重点压力：" .. table.concat(profile.currentPressures or {}, "；"),
        x + 24, h - 208, w - x - 78, "left")
    love.graphics.printf("档案内容受国家安全条例保护。未经授权，不得向目标本人透露。",
        x + 24, h - 132, w - x - 78, "left")
    drawTaskbar(self, terminal, w, h)
end

local function drawEvidence(self, terminal, w, h)
    local log = self.sceneState.evidence
    love.graphics.setColor(0.045, 0.052, 0.046, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.84, 0.90, 0.70, 1)
    love.graphics.print("证据档案 · 自动截获", 28, 22)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.70, 0.84, 0.76, 0.75)
    love.graphics.print("系统只归档异常片段，不替审查员做结论。Enter 标记已读。", 30, 52)

    local entries = log and log.entries or {}
    local listX, listY, listW = 28, 88, 390
    local rowH = 66
    if #entries == 0 then
        love.graphics.setColor(0.68, 0.78, 0.70, 0.72)
        love.graphics.printf("暂无证据。监听频道里的大多数内容都只是日常噪声。", listX, listY, listW, "left")
    end
    for index, entry in ipairs(entries) do
        if index > 8 then break end
        local y = listY + (index - 1) * rowH
        local selected = log.selected == index
        local theme = selected and "primary" or "gray"
        local unread = entry.reviewed and "" or " ●"
        local label = entry.date .. " " .. entry.time .. unread .. "\n"
            .. entry.speaker .. " · " .. entry.frequency .. " MHz"
        if Button.new("evidence_" .. tostring(entry.id), label, listX, y, listW, rowH - 8, theme) then
            log.selected = index
        end
    end

    local detailX = listX + listW + 32
    local detail = EvidenceLog.selected(log)
    love.graphics.setColor(0.10, 0.115, 0.090, 0.96)
    love.graphics.rectangle("fill", detailX, 88, w - detailX - 30, h - 160, 7)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.94, 0.84, 0.56, 1)
    love.graphics.print(detail and "截获片段" or "无记录", detailX + 24, 112)
    love.graphics.setFont(self.font)
    if detail then
        love.graphics.setColor(0.78, 0.86, 0.76, 0.92)
        love.graphics.print("时间：" .. detail.date .. " " .. detail.time, detailX + 24, 154)
        love.graphics.print("频道：" .. detail.frequency .. " MHz", detailX + 24, 184)
        love.graphics.print("对象：" .. detail.speaker .. "（" .. detail.profession .. "） ⇄ " .. detail.counterpart,
            detailX + 24, 214)
        love.graphics.print("情境：" .. (detail.activity ~= "" and detail.activity or "未记录"), detailX + 24, 244)
        love.graphics.print("话题：" .. (detail.topic ~= "" and detail.topic or "未记录"), detailX + 24, 274)
        love.graphics.setColor(0.93, 0.88, 0.70, 1)
        love.graphics.printf("“" .. detail.quote .. "”", detailX + 24, 326, w - detailX - 78, "left")
        love.graphics.setColor(0.58, 0.70, 0.62, 0.75)
        love.graphics.printf("审查建议：与公民档案、记事本和后续监听相互印证。单条截获片段不足以独立定罪。",
            detailX + 24, h - 202, w - detailX - 78, "left")
    else
        love.graphics.setColor(0.70, 0.78, 0.70, 0.72)
        love.graphics.printf("当监听通话中出现异常信息时，系统会在这里留下时间、频道、说话人和原句。",
            detailX + 24, 154, w - detailX - 78, "left")
    end
    love.graphics.setColor(0.68, 0.82, 0.74, 0.72)
    love.graphics.print("↑/↓ 选择 · Enter 标记已读 · Esc 返回桌面", 30, h - 70)
    drawTaskbar(self, terminal, w, h)
end

local function drawNotes(self, terminal, w, h)
    love.graphics.setColor(0.12, 0.115, 0.095, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.94, 0.88, 0.69, 1)
    love.graphics.print("记事本 · 本地未加密", 28, 22)
    love.graphics.setColor(0.90, 0.86, 0.72, 1)
    love.graphics.rectangle("fill", 28, 68, w - 56, h - 142, 5)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.15, 0.12, 0.085, 1)
    love.graphics.printf(terminal.notes ~= "" and terminal.notes or "在此输入记录……",
        50, 92, w - 100, "left")
    love.graphics.setColor(0.42, 0.34, 0.22, 0.7)
    love.graphics.print("输入文字 · Enter 换行 · Backspace 删除 · Esc 返回桌面", 40, h - 70)
    drawTaskbar(self, terminal, w, h)
end

local function drawSystem(self, terminal, w, h)
    love.graphics.setColor(0.025, 0.045, 0.060, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.55, 0.90, 0.82, 1)
    love.graphics.print("系统信息", 32, 28)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.76, 0.86, 0.84, 0.9)
    local stats = self.llm:debugStats()
    local lines = {
        "操作系统：A-City Residential OS 1.0",
        "终端编号：APT-07-114",
        "当前日期：" .. GameClock.formatDate(self.sceneState.clock),
        "系统时间：" .. GameClock.format(self.sceneState.clock),
        "监听服务：" .. (stats.started and "运行中" or "离线"),
        "待处理生成请求：" .. tostring(stats.pending or 0),
        "网络：本地安全节点 / 受监控",
    }
    for index, line in ipairs(lines) do love.graphics.print(line, 54, 92 + (index - 1) * 38) end
    drawTaskbar(self, terminal, w, h)
end

function TerminalLayer:draw()
    local t = self.sceneState.terminal
    local w, h = love.graphics.getDimensions()
    local margin = 40
    UIContext.beginFrame()

    if t.os.bootTimer > 0 then drawBoot(self, t, w, h); return end
    if t.os.activeApp == "desktop" then drawDesktop(self, t, w, h); return end
    if t.os.activeApp == "archives" then drawArchives(self, t, w, h); return end
    if t.os.activeApp == "evidence" then drawEvidence(self, t, w, h); return end
    if t.os.activeApp == "notes" then drawNotes(self, t, w, h); return end
    if t.os.activeApp == "system" then drawSystem(self, t, w, h); return end

    love.graphics.setColor(0.02, 0.06, 0.03, 0.82)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)

    local logY = 104
    local logH = h - logY - 132

    if t.view == "intercept" then
        if t.interceptMode == "list" then
            drawHeader(self, "城市通讯监听 · 选择频道", "选择一条线路进入监听。", t.status, w, margin)
            local bx, bw = margin, w - margin * 2
            for i, ch in ipairs(self.channels) do
                local by = logY + (i - 1) * 52
                local theme = (i == t.interceptIndex) and "primary" or "gray"
                local label = ch.freq .. " MHz    " .. ch.a.name .. "（" .. ch.a.profession .. "）  ⇄  " .. ch.b.name .. "（" .. ch.b.profession .. "）"
                if Button.new("ch_" .. ch.id, label, bx, by, bw, 44, theme) then
                    t.interceptIndex = i
                    self:enterChannel(i)
                end
            end
            hint(self, "↑/↓ 选择 ·  Enter/点击 进入监听 ·  TAB 切换审讯 ·  Esc 离开终端", margin, h)
        else
            local ch = self.channels[t.interceptIndex]
            drawHeader(self, "监听中 · " .. (ch and (ch.freq .. " MHz") or ""),
                ch and (ch.a.name .. " ⇄ " .. ch.b.name) or nil, t.status, w, margin)
            self:_scrollLog(self.scrollIntercept, t.interceptTranscript, margin, logY, w - margin * 2, logH)
            hint(self, "空格 立即扫描/中断通话 ·  Backspace 返回频道列表 ·  滚轮 翻看 ·  Esc 离开终端", margin, h)
        end
        drawTaskbar(self, t, w, h)
        return
    end

    -- 审讯视图
    local task = tasks[t.taskIndex]
    drawHeader(self, task and task.title or "审查终端", task and task.briefing or nil, t.status, w, margin)
    self:_scrollLog(self.scrollInterrogate, t.transcript, margin, logY, w - margin * 2, logH)
    local ix, iy, iw = self:_inputRect()
    TextInput.draw(self.font, "审查员 > ", t.input or "", ix, iy, iw, t.composition)
    hint(self, "回车 审讯 ·  F1 忠诚 ·  F2 嫌疑 ·  TAB 切换监听 ·  滚轮 翻看 ·  Esc 离开终端", margin, h)
    drawTaskbar(self, t, w, h)
end

return TerminalLayer
