local BaseScene = require("engine.scenes.BaseScene")
local GameLayer = require("samples.musou.layers.GameLayer")
local HUDLayer = require("samples.musou.layers.HUDLayer")

local MusouScene = BaseScene:extend()

function MusouScene:enter()
    print("Scene: Enter Musou")

    love.mouse.setVisible(true)

    self.layers = {}
    self.gameLayer = GameLayer:new()
    self.hudLayer = HUDLayer:new(self.gameLayer)

    table.insert(self.layers, self.gameLayer)
    table.insert(self.layers, self.hudLayer)

    for _, layer in ipairs(self.layers) do
        if layer.enter then layer:enter() end
    end
end

function MusouScene:exit()
    for i = #self.layers, 1, -1 do
        if self.layers[i].exit then self.layers[i]:exit() end
    end

    self.layers = {}
    self.gameLayer = nil
    self.hudLayer = nil
end

function MusouScene:update(dt)
    for _, layer in ipairs(self.layers) do
        if layer.update then layer:update(dt) end
    end
end

function MusouScene:draw()
    for _, layer in ipairs(self.layers) do
        if layer.draw then layer:draw() end
    end
end

function MusouScene:keypressed(key, scancode, isrepeat)
    -- 父类拦截了 Esc（返回 true）就停止，不再传给 layers
    if BaseScene.keypressed(self, key, scancode, isrepeat) then return true end

    if key == "space" and self.gameLayer and self.gameLayer.gameOver then
        self.gameLayer:reset()
        return true
    end

    return self:dispatchToLayers("keypressed", key, scancode, isrepeat)
end

function MusouScene:mousemoved(x, y, dx, dy)
    for _, layer in ipairs(self.layers) do
        if layer.mousemoved then layer:mousemoved(x, y, dx, dy) end
    end
end

function MusouScene:mousepressed(x, y, button)
    for _, layer in ipairs(self.layers) do
        if layer.mousepressed then layer:mousepressed(x, y, button) end
    end
end

function MusouScene:wheelmoved(x, y)
    for _, layer in ipairs(self.layers) do
        if layer.wheelmoved then layer:wheelmoved(x, y) end
    end
end

function MusouScene:resize(width, height)
    for _, layer in ipairs(self.layers or {}) do
        if layer.resize then layer:resize(width, height) end
    end
end

return MusouScene
