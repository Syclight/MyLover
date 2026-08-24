local BaseLayer = require("engine.layers.BaseLayer")
local HUDLayer = BaseLayer:extend()
local ResourceManager = require("engine.managers.ResourceManager")

local SPAWN_INTERVAL  = 3.5
local SIEGE_INTERVAL  = 10.0

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function drawBar(x, y, w, h, val, maxVal, fill, back)
    love.graphics.setColor(back[1], back[2], back[3], back[4] or 1)
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)
    love.graphics.setColor(fill[1], fill[2], fill[3], fill[4] or 1)
    love.graphics.rectangle("fill", x, y, w * clamp(val/maxVal, 0, 1), h, 2, 2)
end

function HUDLayer:new(gameLayer)
    local instance = BaseLayer.new(self)
    instance.gameLayer  = gameLayer
    instance.isGUILayer = true
    return instance
end

function HUDLayer:enter()
    self.uiFont = ResourceManager:get("font_NotoSerifSC-Regular_14")
end

function HUDLayer:draw()
    local game = self.gameLayer
    if not game then return end
    love.graphics.push("all")
    love.graphics.setFont(self.uiFont)
    self:drawHud(game)
    if game.gameOver then self:drawEndScreen(game) end
    love.graphics.pop()
end

-- ── 主 HUD ────────────────────────────────────────────────────────────────

function HUDLayer:drawHud(game)
    local w, h = love.graphics.getDimensions()
    local barW = math.floor(w * 0.26)
    local barH = 20
    local barY = 12

    -- 我方基地（左）
    drawBar(14, barY, barW, barH,
        game.allyBase.hp, game.allyBase.maxHp,
        {0.22,0.65,1.0,1}, {0.06,0.10,0.14,0.95})
    love.graphics.setColor(0.85, 0.92, 1)
    love.graphics.print("我方基地", 14, barY + barH + 3)
    love.graphics.setColor(0.65, 0.75, 0.9)
    love.graphics.print(
        string.format("%d / %d", math.ceil(game.allyBase.hp), game.allyBase.maxHp),
        14, barY + barH + 18)

    -- 敌方要塞（右）
    drawBar(w-14-barW, barY, barW, barH,
        game.fortress.hp, game.fortress.maxHp,
        {1.0,0.28,0.22,1}, {0.14,0.06,0.06,0.95})
    love.graphics.setColor(1, 0.80, 0.78)
    love.graphics.printf("敌方要塞", w-14-barW, barY+barH+3, barW, "right")
    love.graphics.setColor(0.9, 0.62, 0.60)
    love.graphics.printf(
        string.format("%d / %d", math.ceil(game.fortress.hp), game.fortress.maxHp),
        w-14-barW, barY+barH+18, barW, "right")

    -- 中央：时间 + 炮台剩余
    local mm = math.floor(game.elapsed / 60)
    local ss = math.floor(game.elapsed % 60)
    love.graphics.setColor(0.95, 0.90, 0.65)
    love.graphics.printf(string.format("时间  %02d:%02d", mm, ss), 0, barY+2, w, "center")

    -- 炮台 + 守军统计
    local totalT, aliveT = #game.turrets, 0
    for _, t in ipairs(game.turrets) do if t.hp > 0 then aliveT = aliveT + 1 end end
    local totalG, aliveG = #game.garrison, 0
    for _, g in ipairs(game.garrison) do if g.hp > 0 then aliveG = aliveG + 1 end end
    love.graphics.setColor(0.75, 0.78, 0.82)
    love.graphics.printf(
        string.format("炮台: %d/%d  守军: %d/%d  摧毁: %d  得分: %d  兵力: %d",
            aliveT, totalT, aliveG, totalG, game.kills, game.score, #game.allies),
        0, barY+barH+3, w, "center")

    -- 炮击倒计时（右侧顶部小提示）
    local sigeMax = (game.elapsed < 1) and 15.0 or SIEGE_INTERVAL
    local siegeLeft = game.siegeTimer
    if siegeLeft < sigeMax then
        local urgency = siegeLeft < 3.0
        if urgency then
            love.graphics.setColor(1, 0.25, 0.10, 0.95)
        else
            love.graphics.setColor(1, 0.55, 0.18, 0.80)
        end
        love.graphics.printf(
            string.format("⚠ 要塞炮击  %.1f s", siegeLeft),
            w - 14 - barW, barY + barH + 36, barW, "right")
    end

    self:drawBottomPanel(game, w, h)
end

-- ── 底部面板 ──────────────────────────────────────────────────────────────

function HUDLayer:drawBottomPanel(game, w, h)
    local panelH = 88
    local panelY = h - panelH

    love.graphics.setColor(0.05, 0.07, 0.10, 0.92)
    love.graphics.rectangle("fill", 0, panelY, w, panelH)
    love.graphics.setColor(0.20, 0.24, 0.28, 0.80)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, panelY, w, panelY)

    self:drawUnitBar(game, 14, panelY + 10)
    self:drawFormationBar(game, 14, panelY + 54)

    -- 出兵进度（右侧）— 取两个兵营中较快的那个显示
    local ut      = game.unitTypes[game.currentUnitType]
    local barTimer = SPAWN_INTERVAL
    if game.allyBarracks then
        for _, bar in ipairs(game.allyBarracks) do
            if bar.timer < barTimer then barTimer = bar.timer end
        end
    end
    local spawnPct = 1 - (barTimer / SPAWN_INTERVAL)
    local rightX  = w - 230
    local rightW  = 215

    love.graphics.setColor(0.18, 0.20, 0.24, 0.92)
    love.graphics.rectangle("fill", rightX, panelY+10, rightW, 20, 3, 3)
    love.graphics.setColor(ut.color[1], ut.color[2], ut.color[3], 0.88)
    love.graphics.rectangle("fill", rightX, panelY+10, rightW*clamp(spawnPct,0,1), 20, 3, 3)
    love.graphics.setColor(1, 1, 1)
    local cdLabel = barTimer > 0.1
        and string.format("出兵倒计时  %.1f s", barTimer)
        or  "▶  即将出兵！"
    love.graphics.printf(cdLabel, rightX, panelY+13, rightW, "center")

    love.graphics.setColor(ut.color[1], ut.color[2], ut.color[3], 0.85)
    love.graphics.printf(
        string.format("下一波：%s  |  %s", ut.name, game.formations[game.currentFormation].name),
        rightX, panelY+36, rightW, "center")

    love.graphics.setColor(0.45, 0.47, 0.52)
    love.graphics.printf("1-6 / 滚轮  切换兵种    Q / E  切换阵型", rightX, panelY+56, rightW, "center")
    love.graphics.printf("目标：摧毁敌方要塞！   Space 重新开始", rightX, panelY+72, rightW, "center")
end

-- ── 兵种选择栏 ────────────────────────────────────────────────────────────

function HUDLayer:drawUnitBar(game, x, y)
    local slotW = 68
    local slotH = 30
    local gap   = 4

    love.graphics.setColor(0.60, 0.62, 0.68)
    love.graphics.print("兵种:", x, y+8)
    local labelW = 38

    for i, ut in ipairs(game.unitTypes) do
        local isCurrent = (i == game.currentUnitType)
        local sx = x + labelW + (i-1)*(slotW+gap)
        local c  = ut.color
        if isCurrent then
            love.graphics.setColor(c[1]*0.30, c[2]*0.30, c[3]*0.30, 0.95)
        else
            love.graphics.setColor(0.10, 0.12, 0.15, 0.85)
        end
        love.graphics.rectangle("fill", sx, y, slotW, slotH, 4, 4)
        if isCurrent then
            love.graphics.setColor(c[1], c[2], c[3], 1)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.28, 0.30, 0.34, 0.85)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", sx, y, slotW, slotH, 4, 4)
        love.graphics.setLineWidth(1)
        if isCurrent then
            love.graphics.setColor(c[1], c[2], c[3], 1)
        else
            love.graphics.setColor(0.48, 0.50, 0.54)
        end
        love.graphics.printf(i..":"..ut.name, sx, y+8, slotW, "center")
    end
end

-- ── 阵型选择栏 ────────────────────────────────────────────────────────────

function HUDLayer:drawFormationBar(game, x, y)
    local slotW = 80
    local slotH = 22
    local gap   = 5

    love.graphics.setColor(0.60, 0.62, 0.68)
    love.graphics.print("阵型:", x, y+4)
    local labelW = 38

    for i, form in ipairs(game.formations) do
        local isCurrent = (i == game.currentFormation)
        local sx = x + labelW + (i-1)*(slotW+gap)
        if isCurrent then
            love.graphics.setColor(0.16, 0.40, 0.20, 0.95)
        else
            love.graphics.setColor(0.10, 0.12, 0.15, 0.85)
        end
        love.graphics.rectangle("fill", sx, y, slotW, slotH, 4, 4)
        if isCurrent then
            love.graphics.setColor(0.32, 0.88, 0.42, 1)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.28, 0.30, 0.34, 0.85)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", sx, y, slotW, slotH, 4, 4)
        love.graphics.setLineWidth(1)
        if isCurrent then
            love.graphics.setColor(0.55, 1.0, 0.62)
        else
            love.graphics.setColor(0.48, 0.50, 0.54)
        end
        love.graphics.printf(form.name, sx, y+4, slotW, "center")
    end
end

-- ── 结算画面 ──────────────────────────────────────────────────────────────

function HUDLayer:drawEndScreen(game)
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if game.winner == "ally" then
        love.graphics.setColor(0.35, 1.0, 0.48)
        love.graphics.printf("★  要塞攻破  胜利！★", 0, h*0.30, w, "center")
    else
        love.graphics.setColor(1.0, 0.35, 0.28)
        love.graphics.printf("✕  基地陷落  失败  ✕", 0, h*0.30, w, "center")
    end

    local mm = math.floor(game.elapsed / 60)
    local ss = math.floor(game.elapsed % 60)
    -- count destroyed turrets
    local destroyed = 0
    for _, t in ipairs(game.turrets) do
        if t.hp <= 0 then destroyed = destroyed + 1 end
    end
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf(
        string.format("用时 %02d:%02d    摧毁炮台 %d/%d    得分 %d",
            mm, ss, destroyed, #game.turrets, game.score),
        0, h*0.44, w, "center")

    love.graphics.setColor(0.65, 0.66, 0.72)
    love.graphics.printf("按  Space  重新开始", 0, h*0.57, w, "center")
end

return HUDLayer
