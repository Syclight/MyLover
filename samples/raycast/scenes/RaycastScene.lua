-- samples/raycast/scenes/RaycastScene.lua
local BaseScene = require("engine.scenes.BaseScene")
local GameLayer = require("samples.raycast.layers.GameLayer")
local HUDLayer = require("samples.raycast.layers.HUDLayer")

local RaycastScene = BaseScene:extend()

function RaycastScene:enter()
    print("Scene: Enter Raycast")

    self.sceneState = {
        minimap = {
            map = nil,
            player = nil,
            visible = true
        },
        ui = {
            hoveredSprite = nil,
            showDetail = false,
            detailSprite = nil,
            cursor = {
                x = 0,
                y = 0
            }
        }
    }

    local gameLayer = GameLayer:new(self.sceneState)

    self.layers = {
        gameLayer,
        HUDLayer:new(self.sceneState)
    }

    for _, layer in ipairs(self.layers) do
        if layer.enter then
            layer:enter()
        end
    end
end

function RaycastScene:exit()
    for i = #self.layers, 1, -1 do
        local layer = self.layers[i]
        if layer.exit then
            layer:exit()
        end
    end

    self.layers = {}
    self.sceneState = nil
end

function RaycastScene:update(dt)
    for _, layer in ipairs(self.layers) do
        if layer.update then
            layer:update(dt)
        end
    end
end

function RaycastScene:draw()
    for _, layer in ipairs(self.layers) do
        if layer.draw then
            layer:draw()
        end
    end
end

function RaycastScene:keypressed(key, scancode, isrepeat)
    -- 父类拦截了 Esc（返回 true）就停止，不再传给 layers
    if BaseScene.keypressed(self, key, scancode, isrepeat) then return true end
    return self:dispatchToLayers("keypressed", key, scancode, isrepeat)
end

function RaycastScene:mousepressed(x, y, button)
    for _, layer in ipairs(self.layers) do
        if layer.mousepressed then
            layer:mousepressed(x, y, button)
        end
    end
end

function RaycastScene:resize(width, height)
    for _, layer in ipairs(self.layers or {}) do
        if layer.resize then layer:resize(width, height) end
    end
end

return RaycastScene
