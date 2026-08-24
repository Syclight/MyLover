-- 通用地表印花累积器：将任意椭圆印花写入固定世界坐标的状态 Canvas。
-- 通道约定：R=泥土翻起，G=湿润，B=凹坑，A=血迹/自定义深色污渍。
local SurfaceStamps = {}
SurfaceStamps.__index = SurfaceStamps

function SurfaceStamps.new(canvas, bounds)
    local self = setmetatable({
        canvas = assert(canvas, "SurfaceStamps requires a state canvas"),
        bounds = assert(bounds, "SurfaceStamps requires world bounds"),
        pending = {},
        stampCount = 0,
    }, SurfaceStamps)
    self.width, self.height = canvas:getDimensions()
    self:clear()
    return self
end

function SurfaceStamps:clear()
    self.pending = {}
    self.stampCount = 0
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setCanvas()
end

function SurfaceStamps:queueEllipse(stamp)
    local bounds = self.bounds
    if stamp.x < bounds.minX or stamp.x > bounds.maxX or stamp.z < bounds.minZ or stamp.z > bounds.maxZ then return end
    self.pending[#self.pending + 1] = {
        x = stamp.x,
        z = stamp.z,
        radiusX = stamp.radiusX,
        radiusZ = stamp.radiusZ,
        angle = stamp.angle or 0,
        seed = stamp.seed or 0,
        mud = stamp.mud or 0,
        wet = stamp.wet or 0,
        crater = stamp.crater or 0,
        blood = stamp.blood or 0,
        splash = stamp.splash,
    }
end

function SurfaceStamps:render()
    if #self.pending == 0 then return end
    local bounds = self.bounds
    local scaleX = self.width / (bounds.maxX - bounds.minX)
    local scaleZ = self.height / (bounds.maxZ - bounds.minZ)
    love.graphics.setCanvas(self.canvas)
    love.graphics.setShader()
    love.graphics.setBlendMode("add", "premultiplied")
    for _, stamp in ipairs(self.pending) do
        local px = (stamp.x - bounds.minX) * scaleX
        local py = (stamp.z - bounds.minZ) * scaleZ
        love.graphics.setColor(stamp.mud, stamp.wet, stamp.crater, stamp.blood)
        love.graphics.push()
        love.graphics.translate(px, py)
        love.graphics.rotate(stamp.angle)
        love.graphics.ellipse("fill", 0, 0, math.max(1.2, stamp.radiusX * scaleX),
            math.max(1.2, stamp.radiusZ * scaleZ))
        love.graphics.pop()
        if stamp.splash then
            local angle = stamp.seed * math.pi * 2
            love.graphics.setColor(stamp.mud * 0.30, stamp.wet * 0.85, stamp.crater * 0.20, 0)
            love.graphics.ellipse("fill", px + math.cos(angle) * stamp.splash, py + math.sin(angle) * stamp.splash * 0.8,
                1.3, 0.9)
        end
    end
    self.stampCount = self.stampCount + #self.pending
    self.pending = {}
    love.graphics.setCanvas()
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
end

return SurfaceStamps
