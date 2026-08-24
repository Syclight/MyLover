local Books = require("games.surveillance.data.books")

local InventoryBar = {}

local SLOT_SIZE = 58
local SLOT_GAP = 8
local PANEL_PAD = 10

local function layout(state, screenWidth, screenHeight)
    local totalHeight = state.capacity * SLOT_SIZE + (state.capacity - 1) * SLOT_GAP
    local x = screenWidth - SLOT_SIZE - 18
    local y = math.floor((screenHeight - totalHeight) * 0.5)
    return x, y, totalHeight
end

local function drawRemoteIcon(x, y, size)
    local rw, rh = size * 0.34, size * 0.72
    local rx, ry = x + (size - rw) * 0.5, y + (size - rh) * 0.5
    love.graphics.setColor(0.12, 0.13, 0.14, 1)
    love.graphics.rectangle("fill", rx, ry, rw, rh, 5)
    love.graphics.setColor(0.55, 0.82, 0.72, 1)
    love.graphics.rectangle("fill", rx + 4, ry + 5, rw - 8, rh * 0.24, 2)
    love.graphics.setColor(0.76, 0.72, 0.58, 1)
    love.graphics.circle("fill", rx + rw * 0.5, ry + rh * 0.49, 3)
    love.graphics.circle("line", rx + rw * 0.5, ry + rh * 0.68, 4)
end

local function drawBookIcon(x, y, size, bookIndex)
    local color = Books.color(bookIndex)
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.rectangle("fill", x + size * .28, y + size * .18, size * .44, size * .64, 2)
    love.graphics.setColor(.86, .72, .45, .9)
    love.graphics.rectangle("line", x + size * .32, y + size * .23, size * .36, size * .22, 1)
end

function InventoryBar.draw(state, font, screenWidth, screenHeight)
    local startX, startY, totalHeight = layout(state, screenWidth, screenHeight)

    love.graphics.push("all")
    love.graphics.setColor(0.08, 0.065, 0.045, 0.76)
    love.graphics.rectangle("fill", startX - PANEL_PAD, startY - PANEL_PAD,
        SLOT_SIZE + PANEL_PAD * 2, totalHeight + PANEL_PAD * 2, 5)

    for index = 1, state.capacity do
        local sx = startX
        local sy = startY + (index - 1) * (SLOT_SIZE + SLOT_GAP)
        local selected = state.selectedSlot == index

        love.graphics.setColor(selected and { 0.36, 0.29, 0.16, 0.96 } or { 0.18, 0.15, 0.10, 0.94 })
        love.graphics.rectangle("fill", sx, sy, SLOT_SIZE, SLOT_SIZE, 3)
        love.graphics.setLineWidth(selected and 3 or 1)
        love.graphics.setColor(selected and { 0.95, 0.77, 0.35, 1 }
            or { 0.48, 0.40, 0.27, 1 })
        love.graphics.rectangle("line", sx, sy, SLOT_SIZE, SLOT_SIZE, 3)

        local item = state.slots[index]
        if item and item.icon == "remote" then drawRemoteIcon(sx, sy, SLOT_SIZE) end
        if item and item.icon == "book" then drawBookIcon(sx, sy, SLOT_SIZE, item.bookIndex) end
        love.graphics.setFont(font)
        love.graphics.setColor(0.92, 0.84, 0.65, 0.8)
        love.graphics.print(tostring(index), sx + 5, sy + 3)
    end

    love.graphics.setFont(font)
    love.graphics.setColor(0.92, 0.84, 0.66, 0.75)
    love.graphics.printf("物品栏", startX - 6, startY - 25, SLOT_SIZE + 12, "center")
    love.graphics.printf("[0] 空手", startX - 6, startY + totalHeight + 8, SLOT_SIZE + 12, "center")
    love.graphics.pop()
end

return InventoryBar
