local BaseLayer = require("engine.layers.BaseLayer")
local UIContext = require("engine.ui.UIContext")

-- 引入所有视图
local Views = {
    MENU = require("samples.breakout.ui.views.MainMenu"),
    HUD = require("samples.breakout.ui.views.HUD"),
    INVENTORY = require("samples.breakout.ui.views.InventoryView")
}

local GUILayer = BaseLayer:extend()

function GUILayer:new(parentScene)
    local instance = {}
    setmetatable(instance, self)
    self.__index = self
    
    instance.parentScene = parentScene -- 保存场景引用
    instance.isGUILayer = true         -- 标记自己是 UI 层 (给 Scene 识别用)
    
    instance.state = "MENU" 
    instance.score = 0
    return instance
end

function GUILayer:update(dt)
    -- 更新 UI 上下文（核心！必须在 update 里调用）
    UIContext.beginFrame()
    if self.state == "MENU" then
        self.parentScene.isPaused = true
    else
         self.parentScene.isPaused = false
    end
end

function GUILayer:draw()
    -- 保存环境，防止 UI 颜色污染游戏层
    love.graphics.push("all")
    
    if self.state == "MENU" then
        self.parentScene.isPaused = true
        Views.MENU.draw(self)
        
    elseif self.state == "HUD" then
        Views.HUD.draw(self, self.score)
        
    elseif self.state == "INVENTORY" then
        -- 当打开背包时，可能背景还需要画 HUD，看你喜好
        self.parentScene.isPaused = true
        Views.HUD.draw(self, self.score)
        Views.INVENTORY.draw(self)
    end
    
    love.graphics.pop()
end

-- 键盘事件：测试用
function GUILayer:keypressed(key)
    if key == "escape" then
        if self.state == "INVENTORY" then
            self.state = "HUD"
        elseif self.state == "HUD" then
            self.state = "MENU"
        end
    end
end

return GUILayer
