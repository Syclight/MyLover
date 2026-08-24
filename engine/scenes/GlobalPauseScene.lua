local SceneManager = require("engine.managers.SceneManager")
local ResourceManager = require("engine.managers.ResourceManager")
local BaseScene = require("engine.scenes.BaseScene")

local GlobalPauseScene = BaseScene:extend()

function GlobalPauseScene:enter()
    print("Entered Global Pause Menu")
    self.titleFont = ResourceManager:getScopeGlobal("font_NotoSerifSC-Regular_40")
    self.bodyFont = ResourceManager:getScopeGlobal("font_NotoSerifSC-Regular_18")
    self.defaultFont = ResourceManager:getScopeGlobal("font_default_12")
end

function GlobalPauseScene:exit()
    self.titleFont, self.bodyFont, self.defaultFont = nil, nil, nil
end

function GlobalPauseScene:update(dt)
    -- 暂停界面本身可以有自己的动画或逻辑更新，目前留空
end

function GlobalPauseScene:draw()
    local w, h = love.graphics.getDimensions()
    
    -- 1. 画一个半透明的黑色遮罩，让底层的游戏画面变暗
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    -- 2. 画出暂停文本 (暂时使用默认字体放大展示)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(self.titleFont)
    love.graphics.printf("PAUSED", 0, h/2 - 60, w, "center")
    
    -- love.graphics.setFont(love.graphics.newFont(16))
    love.graphics.setFont(self.bodyFont)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    -- love.graphics.printf("Press ESC to Resume\nPress Q to Quit Game", 0, h/2 + 20, w, "center")
    love.graphics.printf("按 ESC 键恢复\n按 Q 键退出游戏", 0, h/2 + 20, w, "center")
    
    -- 3. 恢复默认状态，防止影响其他渲染
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(self.defaultFont)
end

function GlobalPauseScene:keypressed(key)
    if key == "escape" then
        -- 核心魔法：弹出当前暂停场景，底层的游戏画面会自动恢复 update
        SceneManager.pop() 
        return true
    elseif key == "q" then
        love.event.quit()
        return true
    end
    return false
end

function GlobalPauseScene:allowsGlobalShortcuts()
    return false
end

return GlobalPauseScene
