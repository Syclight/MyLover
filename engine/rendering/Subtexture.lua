local Subtexture = {}
Subtexture.__index = Subtexture

function Subtexture.new(texture, x, y, width, height)
    local self = setmetatable({}, Subtexture)
    self.texture = texture
    self.x = x
    self.y = y
    self.width  = width
    self.height = height
    local tw, th = texture:getDimensions()
    self.quad = love.graphics.newQuad(x, y, width, height, tw, th)
    return self
end

-- Draw at (x,y), optionally rotated/scaled. Origin defaults to frame center.
function Subtexture:draw(x, y, rotation, scaleX, scaleY, ox, oy)
    love.graphics.draw(
        self.texture,
        self.quad,
        x, y,
        rotation or 0,
        scaleX or 1,
        scaleY or 1,
        ox or (self.width  * 0.5),
        oy or (self.height * 0.5)
    )
end

return Subtexture
