--物品格子

local UIContext = require("engine.ui.UIContext")

local Slot = {}

function Slot.new(id, x, y, size, itemIcon)
    local mx, my = UIContext.mouseX, UIContext.mouseY
    local isHover = mx >= x and mx <= x + size and my >= y and my <= y + size
    
    -- 交互逻辑
    if isHover then
        UIContext.hot = id
        if UIContext.mouseDown then UIContext.active = id end
    end
    
    local isClicked = false
    if UIContext.active == id and not UIContext.mouseDown and isHover then
        UIContext.active = nil
        isClicked = true
    end
    
    -- 渲染逻辑
    love.graphics.setColor(0.2, 0.2, 0.2, 0.8) -- 背景
    love.graphics.rectangle("fill", x, y, size, size, 3)
    
    -- 边框 (悬停高亮)
    if UIContext.hot == id then
        love.graphics.setColor(1, 1, 0) -- 黄色高亮
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, size, size, 3)
    else
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, y, size, size, 3)
    end
    
    -- 如果有物品图标 (这里简单用文字代替，实际应该画 image)
    if itemIcon then
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(itemIcon, x + 5, y + 5)
    end
    
    return isClicked
end

return Slot
