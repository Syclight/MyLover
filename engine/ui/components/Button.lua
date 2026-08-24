local UIContext = require("engine.ui.UIContext")

local Button = {}

-- 定义主题颜色
local themes = {
    primary = { base={0.2, 0.6, 1}, light={0.4, 0.7, 1}, dark={0.1, 0.4, 0.8} },
    danger  = { base={0.9, 0.3, 0.3}, light={1, 0.4, 0.4}, dark={0.7, 0.2, 0.2} },
    gray    = { base={0.5, 0.5, 0.5}, light={0.6, 0.6, 0.6}, dark={0.4, 0.4, 0.4} }
}

function Button.new(id, text, x, y, w, h, themeName)
    local mx, my = UIContext.mouseX, UIContext.mouseY
    local theme = themes[themeName] or themes.primary
    
    -- 1. 判定逻辑
    local isHover = mx >= x and mx <= x + w and my >= y and my <= y + h
    
    if isHover then
        UIContext.hot = id
        if UIContext.mouseDown then
            UIContext.active = id
        end
    end
    
    local isClicked = false
    if UIContext.active == id and not UIContext.mouseDown and isHover then
        UIContext.active = nil
        isClicked = true
    end
    
    -- 2. 渲染
    local color = theme.base
    local yOffset = 0
    local shadow = 4
    
    if UIContext.active == id and isHover then
        color = theme.dark
        yOffset = 4
        shadow = 0
    elseif UIContext.hot == id then
        color = theme.light
    end
    
    -- 阴影
    if shadow > 0 then
        love.graphics.setColor(theme.dark[1]*0.5, theme.dark[2]*0.5, theme.dark[3]*0.5)
        love.graphics.rectangle("fill", x, y+4, w, h, 5)
    end
    
    -- 按钮
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y+yOffset, w, h, 5)
    
    -- 文字
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, x, y+yOffset + (h/2)-6, w, "center")
    
    return isClicked
end

return Button
