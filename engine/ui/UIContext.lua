local UIContext = {
    hot = nil,    -- 当前鼠标悬停的组件ID
    active = nil, -- 当前按下的组件ID
    mouseDown = false,
    mouseX = 0,
    mouseY = 0
}

function UIContext.beginFrame()
    UIContext.hot = nil -- 每帧重置悬停状态，由组件重新声明
    UIContext.mouseX, UIContext.mouseY = love.mouse.getPosition()
    UIContext.mouseDown = love.mouse.isDown(1)
end

return UIContext