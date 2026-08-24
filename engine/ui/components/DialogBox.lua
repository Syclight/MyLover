--对话框

local DialogBox = {}

function DialogBox.draw(title, text)
    local w, h = love.graphics.getDimensions()
    local boxH = 150
    local x, y = 20, h - boxH - 20
    local width = w - 40
    
    -- 半透明背景
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x, y, width, boxH, 10)
    
    -- 边框
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, boxH, 10)
    
    -- 标题
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.print(title, x + 20, y + 15)
    
    -- 内容
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, x + 20, y + 50, width - 40, "left")
    
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.print("Press Space to continue...", x + width - 200, y + boxH - 30)
end

return DialogBox