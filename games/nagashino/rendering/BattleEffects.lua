-- 长筱战斗事件到通用粒子池/地面状态图的映射；不把特效逻辑塞进渲染器。
local BattleEffects = {}
BattleEffects.__index = BattleEffects

function BattleEffects.new(particles, dustParticles, stamps, casualties, craters, weapons)
    return setmetatable({
        particles = particles,
        dustParticles = dustParticles,
        stamps = stamps,
        casualties = casualties,
        craters = craters,
        weapons = weapons,
        nextFormationDust = 0,
        dustEmitted = 0,
    }, BattleEffects)
end

function BattleEffects:emitMuzzleSmoke(event)
    self.particles:emitBurst({
        x = event.x + event.facing * 0.52, y = 0.96, z = event.z,
        radiusX = 0.13, radiusY = 0.10, radiusZ = 0.18,
        vx = event.facing * 0.58, vy = 0.46, vz = 0,
        velocityJitterX = 0.48, velocityJitterY = 0.42, velocityJitterZ = 0.68,
        gravity = 0.10, drag = 1.05,
        sizeMin = 0.30, sizeMax = 0.48, sizeEnd = 1.22,
        lifetimeMin = 1.05, lifetimeMax = 1.65,
        startColor = { 0.48, 0.47, 0.40, 0.92 },
        endColor = { 0.68, 0.63, 0.51, 0.0 },
        spinMin = -1.5, spinMax = 1.5,
        count = 6,
    })
    self.particles:emitBurst({
        x = event.x + event.facing * 0.58, y = 0.96, z = event.z,
        vx = event.facing * 0.16, vy = 0.08,
        sizeMin = 0.30, sizeMax = 0.42, sizeEnd = 0.12,
        lifetimeMin = 0.07, lifetimeMax = 0.12,
        startColor = { 1.00, 0.72, 0.22, 0.98 },
        endColor = { 1.00, 0.22, 0.04, 0.0 },
        count = 1,
    })
end

function BattleEffects:emitImpact(event)
    self.particles:emitBurst({
        x = event.x, y = 0.08, z = event.z,
        radiusX = 0, radiusZ = 0,
        vx = (event.facing or 0) * 0.20, vy = 0.78, vz = 0,
        velocityJitterX = 0.16, velocityJitterY = 0.36, velocityJitterZ = 0.18,
        gravity = -3.0, drag = 2.65,
        sizeMin = 0.10, sizeMax = 0.16, sizeEnd = 0.045,
        lifetimeMin = 0.30, lifetimeMax = 0.52,
        startColor = { 0.43, 0.25, 0.12, 0.96 },
        endColor = { 0.23, 0.14, 0.08, 0.0 },
        spinMin = -5, spinMax = 5,
        count = 7,
    })
    if self.craters then self.craters:add(event.x, event.z, event.seed, event.facing) end
    self.stamps:queueCrater(event.x, event.z, event.seed, event.facing)
end

function BattleEffects:emitHorseDust(unit)
    self.dustParticles:emitBurst({
        x = unit.x - unit.facing * 0.48, y = 0.34, z = unit.z,
        radiusX = 0.62, radiusY = 0.16, radiusZ = 0.58,
        vx = -unit.facing * 0.46, vy = 0.48, vz = 0,
        velocityJitterX = 0.96, velocityJitterY = 0.52, velocityJitterZ = 1.12,
        gravity = 0.07, drag = 1.15,
        sizeMin = 0.52, sizeMax = 0.80, sizeEnd = 2.05,
        lifetimeMin = 1.05, lifetimeMax = 1.58,
        startColor = { 0.96, 0.70, 0.36, 0.82 },
        endColor = { 0.78, 0.59, 0.34, 0.0 },
        spinMin = -0.8, spinMax = 0.8,
        count = unit.speed > 4.25 and 2 or 1,
    })
    self.dustEmitted = self.dustEmitted + 1
end

-- 横队共享的低密度尘幕：中远景先读到冲锋体量，再读到单匹马的蹄后细尘。
function BattleEffects:emitFormationDust(unit)
    self.dustParticles:emitBurst({
        x = unit.x - unit.facing * 0.86, y = 0.78, z = unit.z,
        radiusX = 0.62, radiusY = 0.32, radiusZ = 0.82,
        vx = -unit.facing * 0.30, vy = 0.28, vz = 0,
        velocityJitterX = 0.46, velocityJitterY = 0.30, velocityJitterZ = 0.70,
        gravity = 0.03, drag = 0.62,
        sizeMin = 1.28, sizeMax = 1.82, sizeEnd = 3.10,
        lifetimeMin = 1.25, lifetimeMax = 1.85,
        startColor = { 0.82, 0.60, 0.32, 0.34 },
        endColor = { 0.72, 0.55, 0.34, 0.0 },
        spinMin = -0.25, spinMax = 0.25,
        count = 1,
    })
    self.dustEmitted = self.dustEmitted + 1
end

function BattleEffects:update(simulation, dt)
    for _, event in ipairs(simulation:drainEvents()) do
        if event.type == "muzzle" then
            self:emitMuzzleSmoke(event)
        elseif event.type == "impact" then
            self:emitImpact(event)
        elseif event.type == "blood" then
            self.stamps:queueBlood(event.x, event.z, event.seed)
        elseif event.type == "casualty" and self.casualties then
            self.casualties:add(event)
            self.stamps:queueCorpse(event.x, event.z, event.seed, event.facing, event.role)
        elseif event.type == "weapon" and self.weapons then
            self.weapons:add(event)
        end
    end

    for _, unit in ipairs(simulation.units) do
        if unit.alive and unit.role == "cavalry" and unit.speed > 0.65 then
            local nextDust = unit.nextDustTime or (simulation.time + unit.seed * 0.20)
            if simulation.time >= nextDust then
                self:emitHorseDust(unit)
                unit.nextDustTime = simulation.time + 0.16 + unit.seed * 0.11
            end
        end
    end
    if simulation.phase == "charge" and simulation.time >= self.nextFormationDust then
        for _, unit in ipairs(simulation.units) do
            -- 每隔三列放一个尘源，横队两翼也有起尘，同时避免形成整齐的雾墙。
            if unit.alive and unit.role == "cavalry" and unit.column % 3 == 1 then
                self:emitFormationDust(unit)
            end
        end
        self.nextFormationDust = simulation.time + 0.42
    end
    self.particles:update(dt)
    self.dustParticles:update(dt)
end

function BattleEffects:clear()
    self.particles:clear()
    self.dustParticles:clear()
    if self.casualties then self.casualties:clear() end
    if self.craters then self.craters:clear() end
    if self.weapons then self.weapons:clear() end
    self.nextFormationDust = 0
    self.dustEmitted = 0
end

return BattleEffects
