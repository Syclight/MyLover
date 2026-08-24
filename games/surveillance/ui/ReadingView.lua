local Books = require("games.surveillance.data.books")
local ReadingSystem = require("games.surveillance.gameplay.ReadingSystem")

local ReadingView = {}

function ReadingView.draw(state, bodyFont, titleFont, screenWidth, screenHeight)
    if not state.open then return end
    local book = Books.get(state.bookIndex)
    local pageText = (book.pages or {})[state.page] or "这一页是空白的。"
    local width = math.min(900, screenWidth - 120)
    local height = math.min(560, screenHeight - 100)
    local x, y = (screenWidth - width) * 0.5, (screenHeight - height) * 0.5
    local half = width * 0.5

    love.graphics.push("all")
    love.graphics.setColor(0.01, 0.012, 0.015, 0.88)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
    love.graphics.setColor(0.20, 0.10, 0.065, 1)
    love.graphics.rectangle("fill", x - 10, y - 10, width + 20, height + 20, 9)
    love.graphics.setColor(0.84, 0.79, 0.65, 1)
    love.graphics.rectangle("fill", x, y, half, height, 5, 0)
    love.graphics.setColor(0.89, 0.85, 0.72, 1)
    love.graphics.rectangle("fill", x + half, y, half, height, 0, 5)
    love.graphics.setColor(0.30, 0.22, 0.14, 0.28)
    love.graphics.rectangle("fill", x + half - 5, y, 10, height)

    local cover = book.color
    love.graphics.setColor(cover[1], cover[2], cover[3], 1)
    love.graphics.rectangle("fill", x + 70, y + 75, half - 140, height - 150, 5)
    love.graphics.setColor(0.90, 0.78, 0.50, 0.9)
    love.graphics.rectangle("line", x + 90, y + 100, half - 180, 100, 3)
    love.graphics.setFont(titleFont)
    love.graphics.printf(book.title, x + 105, y + 125, half - 210, "center")

    love.graphics.setColor(0.16, 0.12, 0.085, 1)
    love.graphics.printf(book.title, x + half + 40, y + 48, half - 80, "center")
    love.graphics.setFont(bodyFont)
    love.graphics.printf(pageText, x + half + 54, y + 112, half - 108, "left")
    love.graphics.setColor(0.25, 0.18, 0.11, 0.65)
    love.graphics.printf(string.format("— %d / %d —", state.page, ReadingSystem.pageCount(state)),
        x + half + 40, y + height - 58, half - 80, "center")
    love.graphics.setColor(0.92, 0.88, 0.76, 0.78)
    love.graphics.printf("[←/→ 或 A/D] 翻页   [滚轮] 翻页   [R/Esc] 合上",
        x, y + height + 28, width, "center")
    love.graphics.pop()
end

return ReadingView
