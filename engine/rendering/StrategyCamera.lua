local Vec3 = require("engine.math.Vec3")

local StrategyCamera = {}
StrategyCamera.__index = StrategyCamera

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function distanceToBoundary(origin, direction, minValue, maxValue)
    if direction > 1e-6 then return (maxValue - origin) / direction end
    if direction < -1e-6 then return (minValue - origin) / direction end
    return math.huge
end

function StrategyCamera.new(camera, options)
    assert(camera, "StrategyCamera requires a Camera3D")
    options = options or {}

    local self = setmetatable({}, StrategyCamera)
    self.camera = camera
    self.target = Vec3.new()
    self.yaw = options.yaw or 0
    self.pitch = options.pitch or math.rad(35)
    self.distance = options.distance or 35
    self.effectiveDistance = self.distance
    self.minDistance = options.minDistance or 8
    self.maxDistance = options.maxDistance or 70
    self.minPitch = options.minPitch or math.rad(15)
    self.maxPitch = options.maxPitch or math.rad(70)
    self.zoomSpeed = options.zoomSpeed or 0.12
    self.orbitSpeedX = options.orbitSpeedX or 0.006
    self.orbitSpeedY = options.orbitSpeedY or 0.0045
    self.edgePadding = options.edgePadding or 1.5
    self.targetBounds = options.targetBounds or {
        minX = -math.huge, maxX = math.huge,
        minZ = -math.huge, maxZ = math.huge,
    }
    self.eyeBounds = options.eyeBounds or self.targetBounds
    self.minEyeHeight = options.minEyeHeight or 2
    self.maxEyeHeight = options.maxEyeHeight or math.huge
    self:setTarget(options.targetX or 0, options.targetY or 0, options.targetZ or 0)
    return self
end

function StrategyCamera:setTarget(x, y, z)
    self.target:set(x, y, z)
    return self:clampTarget()
end

function StrategyCamera:clampTarget()
    local bounds = self.targetBounds
    self.target.x = clamp(self.target.x, bounds.minX, bounds.maxX)
    self.target.z = clamp(self.target.z, bounds.minZ, bounds.maxZ)
    return self
end

function StrategyCamera:pan(dx, dz)
    self.target.x = self.target.x + dx
    self.target.z = self.target.z + dz
    return self:clampTarget()
end

function StrategyCamera:orbitPixels(dx, dy)
    self.yaw = self.yaw + dx * self.orbitSpeedX
    self.pitch = clamp(self.pitch + dy * self.orbitSpeedY, self.minPitch, self.maxPitch)
    return self
end

function StrategyCamera:zoom(wheelY)
    self.distance = clamp(self.distance * (1 - wheelY * self.zoomSpeed), self.minDistance, self.maxDistance)
    return self
end

function StrategyCamera:maxDistanceForCurrentView()
    local horizontal = math.cos(self.pitch)
    local vertical = math.sin(self.pitch)
    local dirX = math.cos(self.yaw)
    local dirZ = math.sin(self.yaw)
    local bounds = self.eyeBounds

    local maxHorizontal = math.min(
        distanceToBoundary(self.target.x, dirX, bounds.minX, bounds.maxX),
        distanceToBoundary(self.target.z, dirZ, bounds.minZ, bounds.maxZ)
    ) - self.edgePadding
    local maxByPlanarBounds = maxHorizontal / math.max(horizontal, 1e-4)
    local maxByHeight = (self.maxEyeHeight - self.target.y) / math.max(vertical, 1e-4)
    return clamp(math.min(self.maxDistance, maxByPlanarBounds, maxByHeight), self.minDistance, self.maxDistance)
end

function StrategyCamera:update()
    self:clampTarget()
    self.effectiveDistance = math.min(self.distance, self:maxDistanceForCurrentView())

    local horizontal = math.cos(self.pitch) * self.effectiveDistance
    local x = self.target.x + math.cos(self.yaw) * horizontal
    local y = self.target.y + math.sin(self.pitch) * self.effectiveDistance
    local z = self.target.z + math.sin(self.yaw) * horizontal
    y = clamp(y, self.minEyeHeight, self.maxEyeHeight)

    self.camera:setPosition(x, y, z)
    self.camera:lookAt(self.target.x, self.target.y, self.target.z)
    return self
end

return StrategyCamera
