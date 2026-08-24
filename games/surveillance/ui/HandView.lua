local Books = require("games.surveillance.data.books")

local HandView = {}

local function approach(value, target, speed, dt)
    return value + (target - value) * (1 - math.exp(-speed * dt))
end

function HandView.new()
    return { raise = 0, swayX = 0, swayY = 0, lookX = 0, lookY = 0, action = 0, walkTime = 0 }
end

function HandView.look(state, dx, dy)
    state.lookX = math.max(-22, math.min(22, state.lookX + dx * 0.75))
    state.lookY = math.max(-14, math.min(14, state.lookY + dy * 0.55))
end

function HandView.pulse(state)
    state.action = 1
end

function HandView.update(state, dt, item)
    local visible = item ~= nil
    state.item = item
    state.raise = approach(state.raise, visible and 1 or 0, visible and 9 or 13, dt)
    state.lookX = approach(state.lookX, 0, 9, dt)
    state.lookY = approach(state.lookY, 0, 9, dt)
    state.action = approach(state.action, 0, 14, dt)
    local moving = love.keyboard.isDown("w", "a", "s", "d", "up", "down", "left", "right")
    if moving then state.walkTime = state.walkTime + dt * 8.5 end
    state.swayX = approach(state.swayX, moving and math.sin(state.walkTime) * 8 or 0, 10, dt)
    state.swayY = approach(state.swayY, moving and math.abs(math.cos(state.walkTime)) * 7 or 0, 10, dt)
end

local function drawRemote(ac)
    love.graphics.setColor(0.035, 0.04, 0.045, 0.95)
    love.graphics.polygon("fill", -54, -162, 42, -151, 58, 92, -46, 104)
    love.graphics.setColor(0.12, 0.135, 0.145, 1)
    love.graphics.polygon("fill", -46, -170, 47, -158, 44, 92, -42, 101)
    love.graphics.setColor(0.22, 0.24, 0.25, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", -46, -170, 47, -158, 44, 92, -42, 101)

    love.graphics.setColor(ac and ac.power and { 0.48, 0.78, 0.65, 1 } or { 0.28, 0.34, 0.32, 1 })
    love.graphics.polygon("fill", -31, -142, 31, -135, 30, -76, -30, -80)
    love.graphics.setColor(0.04, 0.10, 0.085, 0.9)
    love.graphics.printf((ac and tostring(ac.temp) or "--") .. "°", -28, -129, 56, "center")
    love.graphics.printf(ac and (ac.mode == "heat" and "HEAT" or "COOL") or "OFF", -28, -103, 56, "center")

    love.graphics.setColor(0.68, 0.20, 0.17, 1)
    love.graphics.circle("fill", 0, -52, 9)
    love.graphics.setColor(0.48, 0.51, 0.52, 1)
    for row = 0, 2 do
        for col = 0, 1 do love.graphics.circle("fill", -15 + col * 30, -20 + row * 31, 8) end
    end
    love.graphics.setColor(0.75, 0.77, 0.76, 0.45)
    love.graphics.line(-35, -155, -34, 78)
end

local function drawHand()
    love.graphics.setColor(0.16, 0.10, 0.075, 0.28)
    love.graphics.ellipse("fill", 18, 111, 83, 46)
    love.graphics.setColor(0.66, 0.45, 0.32, 1)
    love.graphics.polygon("fill", 4, 72, 62, 63, 112, 151, 35, 179, -5, 112)
    love.graphics.setColor(0.78, 0.56, 0.41, 1)
    love.graphics.ellipse("fill", 22, 87, 47, 34)
    love.graphics.polygon("fill", 30, 74, 58, 56, 67, 69, 45, 104)
    love.graphics.setColor(0.48, 0.31, 0.23, 0.65)
    love.graphics.line(2, 103, 43, 111, 66, 91)
    love.graphics.setColor(0.11, 0.12, 0.14, 1)
    love.graphics.polygon("fill", 38, 148, 114, 126, 151, 205, 52, 225)
end

local function drawBook(item)
    local color = Books.color(item.bookIndex)
    love.graphics.setColor(0.05, 0.035, 0.025, 1)
    love.graphics.polygon("fill", -69, -166, 52, -149, 61, 85, -61, 102)
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.polygon("fill", -61, -174, 55, -156, 52, 79, -57, 94)
    love.graphics.setColor(0.78, 0.68, 0.47, 0.85)
    love.graphics.rectangle("fill", -43, -126, 80, 44, 2)
    love.graphics.setColor(0.13, 0.09, 0.055, 0.9)
    love.graphics.printf(item.name or "书", -39, -118, 72, "center")
    love.graphics.setColor(0.94, 0.88, 0.72, 0.75)
    for page = 0, 5 do love.graphics.line(-50, 84 + page * 2, 48, 70 + page * 2) end
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.line(-49, -157, -47, 74)
end

function HandView.draw(state, item, ac, font, screenWidth, screenHeight)
    if state.raise < 0.015 then return end
    local x = screenWidth * 0.76 + state.swayX - state.lookX
    local y = screenHeight - 138 + state.swayY - state.lookY + (1 - state.raise) * 260 + state.action * 9
    local scale = math.max(0.78, math.min(1.18, screenHeight / 720))
    love.graphics.push("all")
    love.graphics.translate(x, y)
    love.graphics.rotate(0.10 + state.swayX * 0.0018 + state.lookX * 0.0025)
    love.graphics.scale(scale)
    love.graphics.setFont(font)
    drawHand()
    if item and item.icon == "book" then drawBook(item) else drawRemote(ac) end
    love.graphics.pop()
end

return HandView
