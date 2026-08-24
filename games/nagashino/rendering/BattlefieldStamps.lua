-- 长筱的地面行为采集：通用 Canvas 队列与渲染位于 engine.rendering.SurfaceStamps。
local SurfaceStamps = require("engine.rendering.SurfaceStamps")
local BattlefieldStamps = {}
BattlefieldStamps.__index = BattlefieldStamps

local function squaredDistance(ax, az, bx, bz)
    local dx, dz = ax - bx, az - bz
    return dx * dx + dz * dz
end

local function noise01(seed, index, channel)
    local value = math.sin(seed * 93.173 + index * 17.819 + channel * 41.271) * 43758.5453
    return value - math.floor(value)
end

function BattlefieldStamps.new(canvas, bounds)
    local self = SurfaceStamps.new(canvas, bounds)
    return setmetatable(self, BattlefieldStamps)
end

BattlefieldStamps.clear = SurfaceStamps.clear
BattlefieldStamps.render = SurfaceStamps.render
BattlefieldStamps.queueEllipse = SurfaceStamps.queueEllipse

function BattlefieldStamps:queue(x, z, radiusX, radiusZ, mud, wet, seed, angle, blood, crater, splash)
    self:queueEllipse({
        x = x, z = z, radiusX = radiusX, radiusZ = radiusZ,
        mud = mud, wet = wet, blood = blood, crater = crater,
        seed = seed, angle = angle, splash = splash,
    })
end

function BattlefieldStamps:queueBlood(x, z, seed)
    local angle = (seed or 0) * math.pi * 2
    self:queue(x, z, 0.38, 0.23, 0, 0, seed, angle, 0.22)
    self:queue(x + math.cos(angle) * 0.33, z + math.sin(angle) * 0.28,
        0.13, 0.085, 0, 0, (seed or 0) + 0.37, angle + 0.75, 0.11)
end

-- 遗体会把草压低并将泥水挤到身体边缘；这是低频状态印花，不会随镜头抖动。
function BattlefieldStamps:queueCorpse(x, z, seed, facing, role)
    local cavalry = role == "cavalry"
    local angle = (facing or 1) >= 0 and 0 or math.pi
    angle = angle + math.sin((seed or 0) * 59.7) * 0.24
    local length = cavalry and 0.72 or 0.44
    local width = cavalry and 0.38 or 0.25
    self:queue(x, z, length, width, cavalry and 0.088 or 0.056, cavalry and 0.034 or 0.020,
        seed, angle)
    local side = (seed or 0) > 0.5 and 1 or -1
    self:queue(x + math.sin(angle) * side * width * 0.68, z - math.cos(angle) * side * width * 0.68,
        length * 0.56, width * 0.38, cavalry and 0.040 or 0.026, cavalry and 0.017 or 0.010,
        (seed or 0) + 0.31, angle + 0.12)
end

function BattlefieldStamps:queueCrater(x, z, seed, facing)
    local direction = facing and (facing >= 0 and 0 or math.pi) or (seed or 0) * math.pi * 2
    local angle = direction + math.sin((seed or 0) * 71.3) * 0.19
    self:queue(x, z, 0.31, 0.14, 0.030, 0.012, seed, angle, 0, 0.44)
    self:queue(x - math.cos(angle) * 0.19, z - math.sin(angle) * 0.19,
        0.24, 0.055, 0.020, 0.006, (seed or 0) + 0.61, angle, 0, 0.18)
    for index = 1, 3 do
        local a = angle + index * 2.18 + math.sin(seed * 41 + index) * 0.42
        local distance = 0.19 + index * 0.055
        self:queue(x + math.cos(a) * distance, z + math.sin(a) * distance,
            0.055, 0.036, 0.016, 0.004, seed + index * 0.29, a, 0, 0, 3.8)
    end
end

function BattlefieldStamps:collect(simulation)
    for _, unit in ipairs(simulation.units) do
        if unit.alive and not unit.preparationStamped then
            local isCavalry = unit.role == "cavalry"
            local count = isCavalry and 5 or 2
            for index = 1, count do
                local jitter = unit.seed * 31.7 + index * 2.41
                local offsetX = math.sin(jitter * 1.7) * (isCavalry and 0.46 or 0.28)
                local offsetZ = math.cos(jitter * 2.3) * (isCavalry and 0.38 or 0.24)
                self:queue(unit.x + offsetX, unit.z + offsetZ,
                    isCavalry and 0.20 or 0.08, isCavalry and 0.12 or 0.15,
                    isCavalry and 0.050 or 0.018, isCavalry and 0.016 or 0.006,
                    jitter, (unit.facing > 0 and 0 or math.pi) + math.sin(jitter) * 0.48)
            end
            unit.preparationStamped = true
        end

        if unit.alive and unit.speed <= 0.18 then
            local nextIdleStamp = unit.nextIdleStamp or (0.35 + unit.seed * 1.25)
            if simulation.time >= nextIdleStamp then
                unit.idleStampIndex = (unit.idleStampIndex or 0) + 1
                local stampIndex = unit.idleStampIndex
                local jitter = simulation.time * 0.73 + unit.seed * 29.1 + stampIndex * 0.91
                local isCavalry = unit.role == "cavalry"
                self:queue(unit.x + math.sin(jitter * 1.9) * (isCavalry and 0.52 or 0.30),
                    unit.z + math.cos(jitter * 2.7) * (isCavalry and 0.44 or 0.24),
                    isCavalry and 0.17 or 0.07, isCavalry and 0.11 or 0.13,
                    isCavalry and 0.030 or 0.012, isCavalry and 0.010 or 0.004,
                    jitter, (unit.facing > 0 and 0 or math.pi) + math.sin(jitter) * 0.65)
                unit.nextIdleStamp = simulation.time + 0.80 + unit.seed * 1.35
            end
        end

        if unit.alive and unit.speed > 0.18 then
            local isCavalry = unit.role == "cavalry"
            local spacing = isCavalry and 0.30 or 0.58
            if not unit.stampX or squaredDistance(unit.x, unit.z, unit.stampX, unit.stampZ) >= spacing * spacing then
                unit.stampX, unit.stampZ = unit.x, unit.z
                unit.stampIndex = (unit.stampIndex or 0) + 1
                local stampIndex = unit.stampIndex
                local mud = isCavalry and 0.105 or 0.040
                local wet = isCavalry and 0.032 or 0.010
                local side = isCavalry and 0.18 or 0.06
                local direction = unit.facing > 0 and 0 or math.pi
                local jitterX = (noise01(unit.seed, stampIndex, 1) - 0.5) * (isCavalry and 0.20 or 0.09)
                local jitterZ = (noise01(unit.seed, stampIndex, 2) - 0.5) * (isCavalry and 0.28 or 0.12)
                local rotation = (noise01(unit.seed, stampIndex, 3) - 0.5) * 0.34
                self:queue(unit.x + unit.facing * 0.11 + jitterX, unit.z + side + jitterZ,
                    isCavalry and 0.29 or 0.13, isCavalry and 0.18 or 0.07,
                    mud, wet, unit.seed, direction + rotation, 0, 0, isCavalry and 6.0 or nil)
                self:queue(unit.x - unit.facing * 0.11 - jitterX, unit.z - side - jitterZ,
                    isCavalry and 0.29 or 0.13, isCavalry and 0.18 or 0.07,
                    mud, wet, unit.seed + 0.5, direction - rotation, 0, 0, isCavalry and 6.0 or nil)
                if stampIndex % (isCavalry and 3 or 5) == 0 then
                    self:queue(unit.x + jitterX * 1.8, unit.z + jitterZ * 1.8,
                        isCavalry and 0.42 or 0.21, isCavalry and 0.30 or 0.16,
                        mud * 0.58, wet * 0.72, unit.seed + stampIndex, direction + rotation * 1.8)
                end
            end
        end
    end
end

return BattlefieldStamps
