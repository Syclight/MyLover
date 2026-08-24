local GameClock = require("games.surveillance.gameplay.GameClock")

local RestView = {}

function RestView.drawClock(clock, font, screenWidth)
    love.graphics.push("all")
    love.graphics.setFont(font)
    love.graphics.setColor(0.04, 0.045, 0.04, 0.76)
    love.graphics.rectangle("fill", screenWidth - 316, 14, 298, 56, 5)
    love.graphics.setColor(0.90, 0.86, 0.70, 1)
    love.graphics.printf(GameClock.formatDate(clock) .. "  " .. GameClock.format(clock),
        screenWidth - 308, 29, 282, "center")
    love.graphics.pop()
end

function RestView.draw(rest, clock, font, titleFont, screenWidth, screenHeight)
    RestView.drawClock(clock, titleFont, screenWidth)
    if rest.menuOpen then
        local width, height = 500, rest.customMode and 190 or 230
        local x, y = (screenWidth - width) * 0.5, (screenHeight - height) * 0.5
        love.graphics.push("all")
        love.graphics.setColor(0.025, 0.03, 0.035, 0.94)
        love.graphics.rectangle("fill", x, y, width, height, 8)
        love.graphics.setColor(0.72, 0.66, 0.48, 1)
        love.graphics.rectangle("line", x, y, width, height, 8)
        love.graphics.setFont(titleFont)
        love.graphics.setColor(0.96, 0.90, 0.74, 1)
        love.graphics.printf("困意渐渐涌了上来……", x + 20, y + 20, width - 40, "center")
        love.graphics.setFont(font)
        if rest.customMode then
            love.graphics.printf("自定义休息：" .. rest.customHours .. " 小时",
                x + 20, y + 72, width - 40, "center")
            love.graphics.printf("[←/→] 调整  [Enter] 确认  [Esc] 返回",
                x + 20, y + 120, width - 40, "center")
        else
            local lines = {
                "[1] 休息 1 小时", "[2] 休息 2 小时",
                "[3] 自定义时长", "[4] 睡到第二天 06:00", "[Esc] 暂不休息",
            }
            for index, line in ipairs(lines) do
                love.graphics.printf(line, x + 20, y + 62 + (index - 1) * 28, width - 40, "center")
            end
        end
        love.graphics.pop()
    end

    if rest.sleepOverlay > 0 then
        local alpha = math.min(1, rest.sleepOverlay * 1.5)
        love.graphics.push("all")
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
        love.graphics.setFont(titleFont)
        love.graphics.setColor(0.92, 0.90, 0.82, alpha)
        love.graphics.printf(rest.sleepMessage or "你睡着了。", 80, screenHeight * 0.48,
            screenWidth - 160, "center")
        love.graphics.pop()
    end
end

return RestView
