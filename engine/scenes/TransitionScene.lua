local BaseScene = require("engine.scenes.BaseScene")
local SceneManager = require("engine.managers.SceneManager")

local TransitionScene = BaseScene:extend()

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

function TransitionScene:new(options)
    options = options or {}
    local instance = BaseScene.new(self, {
        fromScene = options.fromScene,
        nextScene = assert(options.nextScene, "TransitionScene requires nextScene"),
        duration = options.duration or 0.5,
        color = options.color or { 0, 0, 0 },
        mode = options.mode or "fade",
        elapsed = 0,
        switched = false,
        onComplete = options.onComplete,
    })
    return instance
end

function TransitionScene:progress()
    if self.duration <= 0 then return 1 end
    return clamp(self.elapsed / self.duration, 0, 1)
end

function TransitionScene:alpha()
    local p = self:progress()
    if self.mode == "fadein" then return 1 - p end
    if self.mode == "fadeout" then return p end
    return p < 0.5 and (p * 2) or ((1 - p) * 2)
end

function TransitionScene:update(dt)
    self.elapsed = self.elapsed + dt
    if not self.switched and self:progress() >= 0.5 then
        self.switched = true
        if self.onComplete then self:onComplete() end
    end
    if self:progress() >= 1 then
        SceneManager.switch(self.nextScene)
    end
end

function TransitionScene:draw()
    if self.fromScene and self.fromScene.draw then self.fromScene:draw() end
    local r, g, b = self.color[1] or 0, self.color[2] or 0, self.color[3] or 0
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setColor(r, g, b, self:alpha())
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.pop()
end

function TransitionScene:allowsGlobalShortcuts()
    return false
end

return TransitionScene
