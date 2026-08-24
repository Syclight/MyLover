-- 独立的公寓光投场景（不依赖、不修改任何 ShaderMaze 文件）。
-- 玩家在政府公寓里第一人称走动（walk），走到电脑前按 E 接入终端（terminal），
-- 通过终端完成国家安全部派遣的审查任务（使用引擎注入的异步 LLM 服务）。
local BaseScene = require("engine.scenes.BaseScene")
local RaycastLayer = require("games.surveillance.layers.RaycastLayer")
local HUDLayer = require("games.surveillance.layers.HUDLayer")
local TerminalLayer = require("games.surveillance.layers.TerminalLayer")
local Inventory = require("games.surveillance.gameplay.Inventory")
local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")
local HUDMessages = require("games.surveillance.gameplay.HUDMessages")
local GameClock = require("games.surveillance.gameplay.GameClock")
local EvidenceLog = require("games.surveillance.gameplay.EvidenceLog")
local RestSystem = require("games.surveillance.gameplay.RestSystem")
local ReadingSystem = require("games.surveillance.gameplay.ReadingSystem")
local ReadingView = require("games.surveillance.ui.ReadingView")

local SurveillanceScene = BaseScene:extend()

local function setMode(self, mode)
    if self.sceneState and self.sceneState.transition then
        self.sceneState.transition.alpha = math.max(self.sceneState.transition.alpha or 0, 0.35)
    end
    self.sceneState.apartment.mode = mode
    if mode == "walk" then
        love.mouse.setRelativeMode(true)
        love.mouse.setVisible(false)
        if self.terminal then self.terminal:stopAll() end -- 离开终端即停止监听交互
    else
        love.mouse.setRelativeMode(false)
        love.mouse.setVisible(true)
        if mode == "terminal" and self.terminal then self.terminal:openOS() end
    end
end

function SurveillanceScene:enter()
    assert(self.llm, "SurveillanceScene requires the llm service")
    self.sceneState = {
        apartment = { mode = "walk", canUseComputer = false, hoverDesc = nil },
        messages = HUDMessages.new(),
        evidence = EvidenceLog.new(),
        transition = { alpha = 1.0 },
        clock = GameClock.new({
            startMinutes = 6 * 60, minutesPerSecond = 1,
            startDate = { year = 1984, month = 6, day = 12 },
        }),
        rest = RestSystem.new(),
        reading = ReadingSystem.new(),
        terminal = { transcript = {}, input = "", status = "离线", taskIndex = 1, verdicts = {} },
    }
    self.sceneState.inventory = Inventory.new(5, self.sceneState.messages)
    self.sceneState.monologue = PlayerMonologue.new(self.sceneState.messages)

    self.env = RaycastLayer:new(self.sceneState)
    self.hud = HUDLayer:new(self.sceneState)
    self.terminal = TerminalLayer:new(self.sceneState, self.llm)
    self.layers = { self.env, self.hud, self.terminal }

    for _, layer in ipairs(self.layers) do
        if layer.enter then layer:enter() end
    end

    setMode(self, "walk")
end

function SurveillanceScene:exit()
    for i = #self.layers, 1, -1 do
        if self.layers[i].exit then self.layers[i]:exit() end
    end
    love.mouse.setRelativeMode(false)
    love.mouse.setVisible(true)
    love.keyboard.setTextInput(true) -- 恢复默认文本输入状态，避免影响其它场景/菜单
    self.layers = {}
    self.sceneState = nil
end

function SurveillanceScene:update(dt)
    -- LLM 流式事件由引擎服务逐帧泵送；环境仅 walk 模式更新（terminal 时冻结移动）
    self.terminal:update(dt)
    Inventory.update(self.sceneState.inventory, dt)
    PlayerMonologue.update(self.sceneState.monologue, dt)
    HUDMessages.update(self.sceneState.messages, dt)
    GameClock.update(self.sceneState.clock, dt)
    local transition = self.sceneState.transition
    transition.alpha = math.max(0, (transition.alpha or 0) - dt * 2.8)
    local restEvent = RestSystem.update(self.sceneState.rest, self.sceneState.clock,
        self.env.postureKind, dt)
    if restEvent == "forced_sleep" then
        ReadingSystem.close(self.sceneState.reading)
        if self.env.playerSitting then self.env:standUp() end
        setMode(self, "walk")
    end
    if self.sceneState.apartment.mode == "walk" then
        if not self.sceneState.reading.open and not self.sceneState.rest.menuOpen
            and self.sceneState.rest.sleepOverlay <= 0 then
            self.env:update(dt)
        end
        self.hud:update(dt)
    end
end

function SurveillanceScene:draw()
    if self.sceneState.apartment.mode == "terminal" then
        -- 终端模式:画面冻结且被半透明终端盖住,无需重跑 3D 管线。
        -- 改用上一帧的静态快照当背景(只一次贴图绘制),把 GPU 让给本地 LLM 推理。
        self.env:drawSnapshot()
        self.terminal:draw()
    elseif self.sceneState.reading.open then
        self.env:drawSnapshot()
        ReadingView.draw(self.sceneState.reading, self.hud.titleFont, self.hud.readingTitleFont,
            love.graphics.getDimensions())
        self.hud:drawOverlayOnly()
    else
        self.env:draw() -- 公寓光投打底
        self.hud:draw()
    end
end

function SurveillanceScene:keypressed(key)
    local mode = self.sceneState.apartment.mode
    if self.sceneState.reading.open then
        ReadingSystem.keypressed(self.sceneState.reading, key)
        if not self.sceneState.reading.open then
            love.mouse.setRelativeMode(true)
            love.mouse.setVisible(false)
        end
        return
    end
    if mode == "walk" then
        if self.sceneState.rest.sleepOverlay > 0 then return end
        if RestSystem.keypressed(self.sceneState.rest, self.sceneState.clock, key) then return end
    end
    if key == "escape" then
        if mode == "terminal" then
            -- 监听中 Esc 先返回频道列表（并停止该会话）；否则退出终端
            if not self.terminal:handleEscape() then
                setMode(self, "walk")
            end
        else
            BaseScene.keypressed(self, key) -- 暂停菜单
        end
        return
    end

    if mode == "terminal" then
        self.terminal:keypressed(key)
        return
    end

    -- walk 模式（含"坐下"状态：仅锁定移动，仍可按键交互）
    -- 交互心智模型：E=深入一层 · Q=后退一层 · Esc=退出屏幕/暂停。
    -- Q 在 3D 世界里沿固定阶梯降级（seated→atComputer→home），与到达路径无关，
    -- 不会出现坐↔站横跳；终端是文本输入上下文，其后退由 Esc 负责（避免吞掉打字的 q）。
    local apt = self.sceneState.apartment
    local inventory = self.sceneState.inventory

    if key == "r" and not self.sceneState.rest.menuOpen
        and ReadingSystem.openBook(self.sceneState.reading, Inventory.selected(inventory)) then
        self.sceneState.transition.alpha = 0.35
        love.mouse.setRelativeMode(false)
        love.mouse.setVisible(false)
        return
    end

    if key == "0" or key == "kp0" then
        Inventory.deselect(inventory)
        return
    end

    local slotKey = ({ ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
        kp1 = 1, kp2 = 2, kp3 = 3, kp4 = 4, kp5 = 5 })[key]
    if slotKey then
        Inventory.select(inventory, slotKey)
        return
    elseif key == "tab" then
        Inventory.cycle(inventory, 1)
        return
    end

    -- 遥控器处于手持槽时才能操作空调或放置；数字键只负责切换物品。
    if Inventory.isSelected(inventory, "ac_remote") then
        if key == "p" then
            self.env:acTogglePower()       -- 电源开/关
            self.hud:itemAction()
        elseif key == "m" then
            self.env:acToggleMode()        -- 制冷/制热
            self.hud:itemAction()
        elseif key == "-" or key == "kp-" then
            self.env:acChangeTemp(-1)      -- 温度 −
            self.hud:itemAction()
        elseif key == "=" or key == "kp+" then
            self.env:acChangeTemp(1)       -- 温度 ＋
            self.hud:itemAction()
        elseif key == "e" then
            self.env:placeRemote()         -- 放在准星落点（桌/床/沙发/柜/地面）
        end
        return
    end

    local heldItem = Inventory.selected(inventory)
    if heldItem and heldItem.icon == "book" and key == "e" then
        self.env:placeBook()
        return
    end

    if key == "e" then
        if apt.canUseComputer then
            setMode(self, "terminal")
        elseif apt.canMoveChair then
            self.env:moveChairToComputer() -- 椅子在原位：挪到电脑前
        elseif apt.canSitChair then
            self.env:sitDown()             -- 椅子在电脑前：坐下
        elseif apt.canRest then
            self.env:useRest()             -- 躺到床上或坐到沙发上
        elseif apt.canPickItem then
            self.env:pickUpHovered()       -- 拿起遥控器或书架上的书
        end
    elseif key == "q" then
        if apt.isSitting then
            self.env:standUp()             -- 坐着：起身离开椅子
        elseif apt.canSitChair then
            self.env:returnChairHome()     -- 椅子在电脑前、未坐：归位
        end
    end
end

function SurveillanceScene:textinput(t)
    -- 行走模式下文本输入已关闭（见 TerminalLayer:_applyTextInput），不会有杂散字符
    if self.sceneState.apartment.mode == "terminal" then
        self.terminal:textinput(t)
    end
end

-- 输入法合成串（拼字未上屏的内容）：仅终端模式下交给终端层显示
function SurveillanceScene:textedited(text, start, length)
    if self.sceneState.apartment.mode == "terminal" then
        self.terminal:textedited(text, start, length)
    end
end

function SurveillanceScene:mousemoved(x, y, dx, dy)
    if self.sceneState.apartment.mode == "walk" and not self.sceneState.reading.open
        and not self.sceneState.rest.menuOpen
        and self.sceneState.rest.sleepOverlay <= 0 then
        self.env:mousemoved(x, y, dx, dy)
        self.hud:mousemoved(dx, dy)
    end
end

function SurveillanceScene:wheelmoved(dx, dy)
    if self.sceneState.reading.open then
        ReadingSystem.wheelmoved(self.sceneState.reading, dy)
    elseif self.sceneState.apartment.mode == "terminal" then
        self.terminal:wheelmoved(dx, dy)
    elseif self.sceneState.apartment.mode == "walk" and dy ~= 0
        and not self.sceneState.rest.menuOpen and self.sceneState.rest.sleepOverlay <= 0 then
        Inventory.cycle(self.sceneState.inventory, dy > 0 and -1 or 1)
    end
end

function SurveillanceScene:allowsGlobalShortcuts()
    return self.sceneState == nil or (self.sceneState.apartment.mode ~= "terminal"
        and not self.sceneState.reading.open)
end

function SurveillanceScene:resize(width, height)
    for _, layer in ipairs(self.layers or {}) do
        if layer.resize then layer:resize(width, height) end
    end
end

function SurveillanceScene:pause() end

function SurveillanceScene:resume()
    -- 从暂停菜单返回时恢复鼠标状态
    setMode(self, self.sceneState.apartment.mode)
end

return SurveillanceScene
