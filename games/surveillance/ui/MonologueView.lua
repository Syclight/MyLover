local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")

local MonologueView = {}

function MonologueView.draw(state, font, screenWidth, screenHeight)
    local text, alpha = PlayerMonologue.visible(state)
    if not text or alpha <= 0 then return end
    local width = math.min(720, screenWidth - 80)
    local x = (screenWidth - width) * 0.5
    local padding = 16
    local textHeight = font:getHeight() * 2 + 6
    local y = screenHeight - textHeight - padding * 2 - 18

    love.graphics.push("all")
    love.graphics.setColor(0.025, 0.025, 0.022, 0.58 * alpha)
    love.graphics.rectangle("fill", x, y, width, textHeight + padding * 2, 6)
    love.graphics.setFont(font)
    love.graphics.setColor(0.96, 0.92, 0.82, alpha)
    love.graphics.printf("“" .. text .. "”", x + padding, y + padding,
        width - padding * 2, "center")
    love.graphics.pop()
end

return MonologueView
