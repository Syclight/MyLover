-- samples/breakout/scenes/BreakoutScene.lua
local BaseScene = require("engine.scenes.BaseScene")
local GameLayer = require("samples.breakout.layers.GameLayer")
local GUILayer = require("samples.breakout.layers.GUILayer")

-- 【继承体系】：让 BreakoutScene 继承自 BaseScene
local BreakoutScene = BaseScene:extend()

function BreakoutScene:enter()
    print("Scene: Enter Breakout (OOP Version)")

    love.mouse.setVisible(true)

    self.isPaused = false -- 使用 self 挂载状态
    self.layers = {}      -- 使用 self 挂载图层

    -- addLayer 会自动调用 layer:enter()；layer 的退出与 EventBus 订阅清理
    -- 由 BaseScene 默认的 exit -> exitLayers() 兜底，无需再手写。
    self:addLayer(GameLayer:new())
    self:addLayer(GUILayer:new(self))
end

-- exit / draw / mousepressed / resize 不再覆写：BaseScene 默认实现已转发给 layers。

function BreakoutScene:update(dt)
    for _, layer in ipairs(self.layers) do
        if layer.isGUILayer then
            layer:update(dt)
        elseif not self.isPaused then
            layer:update(dt)
        end
    end
end

function BreakoutScene:keypressed(key, scancode, isrepeat)
    -- 消费约定：父类拦截了 Esc（返回 true）就必须停止，不能再传给 layers
    if BaseScene.keypressed(self, key, scancode, isrepeat) then return true end
    -- 自顶向下分发给 layers，被消费即截断并向上返回结果
    return self:dispatchToLayers("keypressed", key, scancode, isrepeat)
end

return BreakoutScene
