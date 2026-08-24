local Button = require("engine.ui.components.Button")

local HUD = {}

function HUD.draw(layer, score)
    -- 绘制左上角分数
    love.graphics.setColor(1, 1, 0)
    love.graphics.print("SCORE: " .. (score or 0), 20, 20)
    
    -- 右上角暂停按钮
    local w = love.graphics.getWidth()
    if Button.new("pause_btn", "||", w - 60, 20, 40, 40, "gray") then
        layer.state = "MENU" -- 点击暂停回到主菜单
        layer.parentScene.isPaused = true
    end
end

return HUD
