local HUDMessages = require("games.surveillance.gameplay.HUDMessages")

local HUDMessageView = {}

local COLORS = {
    toast = {
        bg = { 0.055, 0.050, 0.040, 0.90 },
        fg = { 0.96, 0.86, 0.58, 1.0 },
        muted = { 0.78, 0.72, 0.58, 0.86 },
    },
    system = {
        bg = { 0.025, 0.055, 0.052, 0.84 },
        fg = { 0.62, 0.96, 0.80, 1.0 },
    },
    monologue = {
        bg = { 0.020, 0.018, 0.015, 0.66 },
        fg = { 0.96, 0.92, 0.82, 1.0 },
    },
}

local function colorWithAlpha(color, alpha)
    return color[1], color[2], color[3], (color[4] or 1) * alpha
end

local function drawSystem(line, alpha, font, screenWidth)
    local width = math.min(520, screenWidth - 160)
    local x, y = (screenWidth - width) * 0.5, 18
    love.graphics.setColor(colorWithAlpha(COLORS.system.bg, alpha))
    love.graphics.rectangle("fill", x, y, width, 36, 4)
    love.graphics.setFont(font)
    love.graphics.setColor(colorWithAlpha(COLORS.system.fg, alpha))
    love.graphics.printf(line.text, x + 14, y + 8, width - 28, "center")
end

local function drawItemCard(line, alpha, font, titleFont, screenWidth)
    local width, height = 340, 70
    -- 右上角卡片避开右侧物品栏与右上时间框，像商业游戏的拾取提示。
    local x, y = screenWidth - width - 118, 86
    love.graphics.setColor(0, 0, 0, 0.22 * alpha)
    love.graphics.rectangle("fill", x + 4, y + 5, width, height, 7)
    love.graphics.setColor(colorWithAlpha(COLORS.toast.bg, alpha))
    love.graphics.rectangle("fill", x, y, width, height, 7)
    love.graphics.setColor(0.95, 0.72, 0.30, 0.85 * alpha)
    love.graphics.rectangle("fill", x, y, 4, height, 7)
    love.graphics.setFont(font)
    love.graphics.setColor(colorWithAlpha(COLORS.toast.muted, alpha))
    love.graphics.print(line.title or "提示", x + 18, y + 10)
    love.graphics.setFont(titleFont)
    love.graphics.setColor(colorWithAlpha(COLORS.toast.fg, alpha))
    love.graphics.print(line.text, x + 18, y + 32)
end

local function drawMonologue(line, alpha, font, screenWidth, screenHeight, ambient)
    local width = math.min(760, screenWidth - 180)
    local x = (screenWidth - width) * 0.5
    local padding = 14
    local textHeight = font:getHeight() * 2 + 4
    local y = screenHeight - textHeight - padding * 2 - 34
    love.graphics.setColor(colorWithAlpha(COLORS.monologue.bg, alpha))
    love.graphics.rectangle("fill", x, y, width, textHeight + padding * 2, 4)
    love.graphics.setFont(font)
    love.graphics.setColor(colorWithAlpha(COLORS.monologue.fg, alpha))
    local text = ambient and line.text or ("“" .. line.text .. "”")
    love.graphics.printf(text, x + padding, y + padding,
        width - padding * 2, "center")
end

function HUDMessageView.hasSubtitle(state, fallbackText)
    local monologue, monologueAlpha = HUDMessages.visible(state, "monologue")
    return (monologue and monologueAlpha > 0) or (fallbackText and fallbackText ~= "")
end

function HUDMessageView.draw(state, font, titleFont, screenWidth, screenHeight, fallbackText)
    love.graphics.push("all")
    local toast, toastAlpha = HUDMessages.visible(state, "toast")
    local system, systemAlpha = HUDMessages.visible(state, "system")
    local monologue, monologueAlpha = HUDMessages.visible(state, "monologue")
    if system and systemAlpha > 0 then
        drawSystem(system, systemAlpha, titleFont, screenWidth)
    end
    if toast and toastAlpha > 0 then
        drawItemCard(toast, toastAlpha, font, titleFont, screenWidth)
    end
    if monologue and monologueAlpha > 0 then
        drawMonologue(monologue, monologueAlpha, titleFont, screenWidth, screenHeight, false)
    elseif fallbackText and fallbackText ~= "" then
        drawMonologue({ text = fallbackText }, 0.82, titleFont, screenWidth, screenHeight, true)
    end
    love.graphics.pop()
end

return HUDMessageView
