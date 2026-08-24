local ResourceManager = require("engine.managers.ResourceManager")
local GameClock = require("games.surveillance.gameplay.GameClock")

local CalendarTexture = {}
local lastKeys = setmetatable({}, { __mode = "k" })

function CalendarTexture.update(canvas, clock)
    if not canvas or not clock then return end
    local date = GameClock.date(clock)
    local key = string.format("%04d-%02d-%02d", date.year, date.month, date.day)
    if lastKeys[canvas] == key then return end
    lastKeys[canvas] = key
    local width, height = canvas:getDimensions()
    local font24 = ResourceManager:getScopeGlobal("font_NotoSerifSC-Regular_24")
    local font40 = ResourceManager:getScopeGlobal("font_NotoSerifSC-Regular_40")
    local weekdayLabels = { "日", "一", "二", "三", "四", "五", "六" }

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.92, 0.89, 0.79, 1)
    love.graphics.setColor(0.48, 0.08, 0.065, 1)
    love.graphics.rectangle("fill", 0, 0, width, 122)
    love.graphics.setColor(0.98, 0.93, 0.82, 1)
    love.graphics.setFont(font40)
    love.graphics.printf(string.format("%04d · %02d", date.year, date.month), 0, 35, width, "center")

    love.graphics.setColor(0.16, 0.10, 0.07, 1)
    love.graphics.push()
    love.graphics.translate(0, 158)
    love.graphics.scale(2.4)
    love.graphics.printf(tostring(date.day), 0, 0, width / 2.4, "center")
    love.graphics.pop()

    love.graphics.setFont(font24)
    love.graphics.setColor(0.30, 0.20, 0.13, 1)
    love.graphics.printf(date.weekdayName, 0, 300, width, "center")
    local cellWidth = width / 7
    for index, label in ipairs(weekdayLabels) do
        local x = (index - 1) * cellWidth
        if index == date.weekday then
            love.graphics.setColor(0.58, 0.10, 0.075, 1)
            love.graphics.rectangle("fill", x + 5, 378, cellWidth - 10, 58, 5)
            love.graphics.setColor(1, 0.94, 0.82, 1)
        else
            love.graphics.setColor(0.28, 0.23, 0.18, 1)
        end
        love.graphics.printf(label, x, 392, cellWidth, "center")
    end
    love.graphics.setColor(0.35, 0.27, 0.19, 0.42)
    love.graphics.setLineWidth(3)
    love.graphics.line(34, 470, width - 34, 470)
    love.graphics.printf("第 " .. GameClock.day(clock) .. " 天", 0, 510, width, "center")
    love.graphics.setCanvas()
    love.graphics.pop()
end

return CalendarTexture
