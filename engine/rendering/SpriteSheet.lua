local Subtexture = require("engine.rendering.Subtexture")

local SpriteSheet = {}
SpriteSheet.__index = SpriteSheet

-- texture     : love Image or Canvas
-- frameWidth  : width of a single frame in pixels
-- frameHeight : height of a single frame in pixels
function SpriteSheet.new(texture, frameWidth, frameHeight)
    local self = setmetatable({}, SpriteSheet)
    self.texture     = texture
    self.frameWidth  = frameWidth
    self.frameHeight = frameHeight
    self._cache      = {}
    return self
end

-- Returns a Subtexture for frame at (row, col), both 0-indexed.
-- Result is cached after first call.
function SpriteSheet:getFrame(row, col)
    local key = row * 1000 + col
    if not self._cache[key] then
        self._cache[key] = Subtexture.new(
            self.texture,
            col * self.frameWidth,
            row * self.frameHeight,
            self.frameWidth,
            self.frameHeight
        )
    end
    return self._cache[key]
end

return SpriteSheet
