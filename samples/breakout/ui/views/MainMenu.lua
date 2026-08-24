local Button = require("engine.ui.components.Button")

local MainMenu = {}

function MainMenu.draw(layer)
    local w, h = love.graphics.getDimensions()
    
    -- 黑色半透明遮罩
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("MY AWESOME GAME", 0, 100, w, "center")
    
    local btnW, btnH = 200, 50
    local cx = (w - btnW) / 2
    local cy = h / 2
    
    -- Start 按钮
    if Button.new("start_btn", "START GAME", cx, cy, btnW, btnH, "primary") then
        layer.state = "HUD" -- 切换状态
        layer.parentScene.isPaused = false -- 继续游戏
    end
    
    -- Inventory 按钮
    if Button.new("inv_btn", "INVENTORY", cx, cy + 70, btnW, btnH, "gray") then
        layer.state = "INVENTORY"
    end
    
    -- Quit 按钮
    if Button.new("quit_btn", "QUIT", cx, cy + 140, btnW, btnH, "danger") then
        love.event.quit()
    end
end

return MainMenu
