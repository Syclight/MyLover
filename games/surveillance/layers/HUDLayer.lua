-- 公寓行走模式 HUD：准星 + “按 E 使用电脑”交互提示。读 sceneState.apartment。
local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")
local Inventory = require("games.surveillance.gameplay.Inventory")
local InventoryBar = require("games.surveillance.ui.InventoryBar")
local HandView = require("games.surveillance.ui.HandView")
local HUDMessageView = require("games.surveillance.ui.HUDMessageView")
local RestView = require("games.surveillance.ui.RestView")

local HUDLayer = BaseLayer:extend()

function HUDLayer:new(sceneState)
    local o = BaseLayer.new(self)
    o.sceneState = sceneState
    o.handView = HandView.new()
    return o
end

function HUDLayer:enter()
    self.font = ResourceManager:get("font_NotoSerifSC-Regular_14")
    self.titleFont = ResourceManager:get("font_NotoSerifSC-Regular_18")
    self.readingTitleFont = ResourceManager:get("font_NotoSerifSC-Regular_24")
end

-- 手持遥控器时的空调控制面板（右下角）。canPlace=当前准星是否有有效落点。
local function drawRemotePanel(self, ac, canPlace, w, h)
    local pw, ph = 300, 210
    local px, py = w - pw - 112, h - ph - 24

    love.graphics.setColor(0.05, 0.08, 0.10, 0.86)
    love.graphics.rectangle("fill", px, py, pw, ph, 8)
    love.graphics.setColor(0.4, 0.8, 0.7, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, pw, ph, 8)

    -- 标题：物品栏当前选中的道具
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(0.7, 1, 0.85, 1)
    love.graphics.print("手持：空调遥控器", px + 14, py + 10)

    love.graphics.setFont(self.font)
    local on = ac.power
    local lineY = py + 44

    love.graphics.setColor(on and { 0.4, 1, 0.5, 1 } or { 1, 0.5, 0.4, 1 })
    love.graphics.print("电源：  " .. (on and "开" or "关"), px + 14, lineY)

    local heat = (ac.mode == "heat")
    local modeColor = heat and { 1.0, 0.55, 0.3, 1 } or { 0.4, 0.7, 1.0, 1 }
    love.graphics.setColor(on and modeColor or { 0.55, 0.55, 0.55, 1 })
    love.graphics.print("模式：  " .. (heat and "制热" or "制冷"), px + 14, lineY + 24)

    love.graphics.setColor(on and { 1, 1, 1, 1 } or { 0.55, 0.55, 0.55, 1 })
    love.graphics.print("温度：  " .. tostring(ac.temp) .. " °C", px + 14, lineY + 48)

    -- 落点状态
    -- if canPlace then
    --     love.graphics.setColor(0.4, 1, 0.6, 1)
    --     love.graphics.print("落点：  可放置", px + 14, lineY + 72)
    -- else
    --     love.graphics.setColor(1, 0.75, 0.35, 1)
    --     love.graphics.print("落点：  够不着（看向桌/床/沙发/柜/地面）", px + 14, lineY + 72)
    -- end

    love.graphics.setColor(0.7, 0.9, 0.8, 0.6)
    love.graphics.print("[P]电源  [M]模式  [ - / + ]温度", px + 14, py + ph - 48)
    love.graphics.print("[E]放在准星处   [0]空手", px + 14, py + ph - 26)
    love.graphics.setColor(1, 1, 1, 1)
end

-- 将旧信息面板替换为屏幕空间的第一人称手持视图模型。
drawRemotePanel = function(self, ac, canPlace, w, h)
    HandView.draw(self.handView, Inventory.selected(self.sceneState.inventory), ac, self.font, w, h)
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.82, 0.92, 0.86, 0.72)
    local subtitleVisible = HUDMessageView.hasSubtitle(self.sceneState.messages, self.sceneState.apartment.hoverDetail)
    love.graphics.printf("[P] 电源  [M] 模式  [-/+] 温度  [E] 放置",
        0, subtitleVisible and (h - 150) or (h - 78), w, "center")
end

function HUDLayer:draw()
    local apartment = self.sceneState.apartment
    local inventory = self.sceneState.inventory
    if not apartment or apartment.mode ~= "walk" then
        return
    end

    local w, h = love.graphics.getDimensions()
    local cx, cy = w * 0.5, h * 0.5
    local subtitleVisible = HUDMessageView.hasSubtitle(self.sceneState.messages, apartment.hoverDetail)
    local heldPromptY = subtitleVisible and (h - 150) or (h - 78)

    -- 空调氛围微染色（开机时）：制冷偏冷蓝、制热偏暖橙，很淡
    local ac = apartment.ac
    if ac and ac.power then
        if ac.mode == "heat" then
            love.graphics.setColor(1.0, 0.5, 0.2, 0.05)
        else
            love.graphics.setColor(0.3, 0.6, 1.0, 0.05)
        end
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- 准星
    local hot = apartment.canUseComputer or apartment.canSitChair or apartment.canMoveChair
        or apartment.canPickItem or apartment.canRest or apartment.canPlaceRemote
        or apartment.canPlaceBook or apartment.canReturnBook
    love.graphics.setColor(hot and { 0.4, 1, 0.6, 1 } or { 1, 1, 1, 0.6 })
    love.graphics.setLineWidth(2)
    love.graphics.line(cx - 8, cy, cx - 3, cy)
    love.graphics.line(cx + 3, cy, cx + 8, cy)
    love.graphics.line(cx, cy - 8, cx, cy - 3)
    love.graphics.line(cx, cy + 3, cx, cy + 8)
    love.graphics.setColor(1, 1, 1, 1)

    -- 交互提示（可同时出现多条，例如坐着面对电脑时：接入 + 起身）
    local prompts = {}
    if apartment.canReturnBook then
        prompts[#prompts + 1] = "[ E ] 把书放回书架"
    elseif apartment.canPlaceBook and Inventory.selected(inventory) then
        prompts[#prompts + 1] = "[ E ] 放置 " .. Inventory.selected(inventory).name
    elseif apartment.canUseComputer then
        prompts[#prompts + 1] = "[ E ] 接入 " .. (apartment.hoverDesc or "终端")
    elseif apartment.canMoveChair then
        prompts[#prompts + 1] = "[ E ] 把椅子挪到电脑前"
    elseif apartment.canSitChair then
        prompts[#prompts + 1] = "[ E ] 坐下"
        prompts[#prompts + 1] = "[ Q ] 椅子归位"
    elseif apartment.canRest then
        prompts[#prompts + 1] = "[ E ] " .. (apartment.restTarget.props.pose == "lie" and "躺到床上" or "坐到沙发上")
    elseif apartment.canPickItem then
        prompts[#prompts + 1] = "[ E ] 拿起 " .. (apartment.hoverDesc or "物品")
    end
    if apartment.isSitting then
        local leaveText = apartment.postureKind == "lie" and "离开床铺"
            or (apartment.postureKind == "sofa" and "离开沙发" or "起身离开椅子")
        prompts[#prompts + 1] = "[ Q ] " .. leaveText
    end

    local remoteSelected = Inventory.isSelected(inventory, "ac_remote")
    -- 选中物品时不显示其它世界交互，避免 E 的用途产生歧义。
    if not remoteSelected and #prompts > 0 then
        love.graphics.setFont(self.titleFont)
        love.graphics.setColor(0.4, 1, 0.6, 1)
        local lineH = self.titleFont:getHeight() + 4
        for i, line in ipairs(prompts) do
            love.graphics.printf(line, 0, cy + 20 + (i - 1) * lineH, w, "center")
        end
        love.graphics.setColor(1, 1, 1, 1)
    elseif not remoteSelected and apartment.hoverDesc then
        love.graphics.setFont(self.font)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.printf(apartment.hoverDesc, 0, cy + 20, w, "center")
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- 选中遥控器：右下角空调控制面板（含落点状态）
    if remoteSelected and apartment.ac then
        drawRemotePanel(self, apartment.ac, apartment.canPlaceRemote, w, h)
    else
        local heldItem = Inventory.selected(inventory)
        if heldItem and heldItem.icon == "book" then
            HandView.draw(self.handView, heldItem, nil, self.font, w, h)
            love.graphics.setFont(self.font)
            love.graphics.setColor(0.82, 0.92, 0.86, 0.72)
            love.graphics.printf("[R] 阅读   [E] 放置/放回书架   [0] 空手", 0, heldPromptY, w, "center")
        end
    end

    InventoryBar.draw(inventory, self.font, w, h)
    HUDMessageView.draw(self.sceneState.messages, self.font, self.titleFont, w, h, apartment.hoverDetail)
    RestView.draw(self.sceneState.rest, self.sceneState.clock, self.font, self.titleFont, w, h)
    self:drawOverlayOnly()
end

function HUDLayer:drawOverlayOnly()
    local transition = self.sceneState.transition
    local alpha = transition and transition.alpha or 0
    if alpha <= 0 then return end
    local w, h = love.graphics.getDimensions()
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, math.min(0.75, alpha))
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.pop()
end

function HUDLayer:update(dt)
    HandView.update(self.handView, dt, Inventory.selected(self.sceneState.inventory))
end

function HUDLayer:mousemoved(dx, dy)
    HandView.look(self.handView, dx, dy)
end

function HUDLayer:itemAction()
    HandView.pulse(self.handView)
end

return HUDLayer
