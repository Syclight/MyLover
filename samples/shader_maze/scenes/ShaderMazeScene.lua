local BaseScene = require("engine.scenes.BaseScene")
local GameLayer = require("samples.shader_maze.layers.GameLayer")
local HUDLayer = require("samples.shader_maze.layers.HUDLayer")

local ShaderMazeScene = BaseScene:extend()

function ShaderMazeScene:enter()
    self.sceneState = {
        minimap = {
            map = nil,
            player = nil,
            visible = true
        },
        ui = {}
    }

    self.layers = {
        GameLayer:new(self.sceneState),
        HUDLayer:new(self.sceneState)
    }

    for _, layer in ipairs(self.layers) do
        if layer.enter then
            layer:enter()
        end
    end
end

function ShaderMazeScene:exit()
    for i = #self.layers, 1, -1 do
        local layer = self.layers[i]
        if layer.exit then
            layer:exit()
        end
    end

    self.layers = {}
    self.sceneState = nil
end

function ShaderMazeScene:update(dt)
    for _, layer in ipairs(self.layers) do
        if layer.update then
            layer:update(dt)
        end
    end
end

function ShaderMazeScene:draw()
    for _, layer in ipairs(self.layers) do
        if layer.draw then
            layer:draw()
        end
    end
end

function ShaderMazeScene:keypressed(key, scancode, isrepeat)
    -- 父类拦截了 Esc（返回 true）就停止，不再传给 layers
    if BaseScene.keypressed(self, key, scancode, isrepeat) then return true end
    return self:dispatchToLayers("keypressed", key, scancode, isrepeat)
end

function ShaderMazeScene:mousemoved(x, y, dx, dy)
    for _, layer in ipairs(self.layers) do
        if layer.mousemoved then
            layer:mousemoved(x, y, dx, dy)
        end
    end
end

function ShaderMazeScene:mousepressed(x, y, button)
    for _, layer in ipairs(self.layers) do
        if layer.mousepressed then
            layer:mousepressed(x, y, button)
        end
    end
end

function ShaderMazeScene:pause()
    for _, layer in ipairs(self.layers) do
        if layer.pause then
            layer:pause()
        end
    end
end

function ShaderMazeScene:resume()
    for _, layer in ipairs(self.layers) do
        if layer.resume then
            layer:resume()
        end
    end
end

function ShaderMazeScene:resize(width, height)
    for _, layer in ipairs(self.layers or {}) do
        if layer.resize then layer:resize(width, height) end
    end
end

return ShaderMazeScene
