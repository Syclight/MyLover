-- 通用、预分配的 3D billboard 粒子池。游戏侧只需调用 emitBurst。
local ParticleSystem = {}
ParticleSystem.__index = ParticleSystem

local BASE_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}

local INSTANCE_FORMAT = {
    { "InstanceCenterSize", "float", 4 },
    { "InstanceColor", "float", 4 },
    { "InstanceRotation", "float", 1 },
}

local QUAD_VERTICES = {
    { -0.5, -0.5, 0, 0, 1 }, { 0.5, -0.5, 0, 1, 1 }, { 0.5, 0.5, 0, 1, 0 },
    { -0.5, -0.5, 0, 0, 1 }, { 0.5, 0.5, 0, 1, 0 }, { -0.5, 0.5, 0, 0, 0 },
}

local function zeroVertex()
    return { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function range(random, min, max)
    min = min or 0
    max = max or min
    return min + (max - min) * random
end

local function colorChannel(color, index, fallback)
    return color and color[index] or fallback
end

function ParticleSystem.new(options)
    options = options or {}
    assert(love.graphics.getSupported().instancing, "ParticleSystem requires GPU instancing")
    local capacity = options.capacity or 512
    local self = setmetatable({
        shader = assert(options.shader, "ParticleSystem requires a shader"),
        texture = assert(options.texture, "ParticleSystem requires a texture"),
        capacity = capacity,
        particles = {},
        instanceVertices = {},
        visible = 0,
        culled = 0,
        active = 0,
        nextSlot = 1,
        randomSeed = options.seed or 0.371,
        depthMode = options.depthMode or "lequal",
    }, ParticleSystem)

    for index = 1, capacity do
        self.particles[index] = { active = false }
        self.instanceVertices[index] = zeroVertex()
    end
    self.instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, self.instanceVertices, "points", "dynamic")
    self.mesh = love.graphics.newMesh(BASE_FORMAT, QUAD_VERTICES, "triangles", "static")
    self.mesh:setTexture(self.texture)
    self.mesh:attachAttribute("InstanceCenterSize", self.instanceMesh, "perinstance")
    self.mesh:attachAttribute("InstanceColor", self.instanceMesh, "perinstance")
    self.mesh:attachAttribute("InstanceRotation", self.instanceMesh, "perinstance")
    return self
end

function ParticleSystem:random()
    self.randomSeed = (self.randomSeed * 16807) % 2147483647
    return (self.randomSeed - 1) / 2147483646
end

function ParticleSystem:allocate()
    for offset = 0, self.capacity - 1 do
        local index = (self.nextSlot + offset - 1) % self.capacity + 1
        local particle = self.particles[index]
        if not particle.active then
            self.nextSlot = index % self.capacity + 1
            self.active = self.active + 1
            return particle
        end
    end
    local particle = self.particles[self.nextSlot]
    self.nextSlot = self.nextSlot % self.capacity + 1
    return particle
end

-- options 支持中心点、随机半径、速度/速度抖动、生命周期、颜色和旋转。
function ParticleSystem:emitBurst(options)
    options = options or {}
    local count = math.max(1, math.floor(options.count or 1))
    local startColor = options.startColor or { 1, 1, 1, 1 }
    local endColor = options.endColor or { startColor[1], startColor[2], startColor[3], 0 }
    for _ = 1, count do
        local particle = self:allocate()
        local random = self:random()
        particle.active = true
        particle.age = 0
        particle.lifetime = math.max(0.016, range(random, options.lifetimeMin or options.lifetime or 0.5,
            options.lifetimeMax or options.lifetime or 0.5))
        particle.x = (options.x or 0) + (self:random() - 0.5) * (options.radiusX or 0)
        particle.y = (options.y or 0) + (self:random() - 0.5) * (options.radiusY or 0)
        particle.z = (options.z or 0) + (self:random() - 0.5) * (options.radiusZ or 0)
        particle.vx = (options.vx or 0) + (self:random() - 0.5) * (options.velocityJitterX or 0)
        particle.vy = (options.vy or 0) + (self:random() - 0.5) * (options.velocityJitterY or 0)
        particle.vz = (options.vz or 0) + (self:random() - 0.5) * (options.velocityJitterZ or 0)
        particle.gravity = options.gravity or 0
        particle.drag = options.drag or 0
        particle.sizeStart = range(self:random(), options.sizeMin or options.size or 0.2,
            options.sizeMax or options.size or 0.2)
        particle.sizeEnd = options.sizeEnd or particle.sizeStart
        particle.rotation = range(self:random(), options.rotationMin or 0, options.rotationMax or math.pi * 2)
        particle.spin = range(self:random(), options.spinMin or 0, options.spinMax or 0)
        particle.startR, particle.startG, particle.startB, particle.startA =
            colorChannel(startColor, 1, 1), colorChannel(startColor, 2, 1),
            colorChannel(startColor, 3, 1), colorChannel(startColor, 4, 1)
        particle.endR, particle.endG, particle.endB, particle.endA =
            colorChannel(endColor, 1, particle.startR), colorChannel(endColor, 2, particle.startG),
            colorChannel(endColor, 3, particle.startB), colorChannel(endColor, 4, 0)
    end
end

function ParticleSystem:update(dt)
    for _, particle in ipairs(self.particles) do
        if particle.active then
            particle.age = particle.age + dt
            if particle.age >= particle.lifetime then
                particle.active = false
                self.active = math.max(0, self.active - 1)
            else
                local damping = math.exp(-particle.drag * dt)
                particle.vx = particle.vx * damping
                particle.vy = particle.vy * damping + particle.gravity * dt
                particle.vz = particle.vz * damping
                particle.x = particle.x + particle.vx * dt
                particle.y = particle.y + particle.vy * dt
                particle.z = particle.z + particle.vz * dt
                particle.rotation = particle.rotation + particle.spin * dt
            end
        end
    end
end

function ParticleSystem:clear()
    for _, particle in ipairs(self.particles) do particle.active = false end
    self.active, self.visible, self.culled = 0, 0, 0
end

function ParticleSystem:buildVisible(camera)
    local visible = 0
    self.culled = 0
    for _, particle in ipairs(self.particles) do
        if particle.active then
            local progress = particle.age / particle.lifetime
            local size = particle.sizeStart + (particle.sizeEnd - particle.sizeStart) * progress
            if camera:isSphereVisible(particle.x, particle.y, particle.z, size * 0.75) then
                visible = visible + 1
                local vertex = self.instanceVertices[visible]
                vertex[1], vertex[2], vertex[3], vertex[4] = particle.x, particle.y, particle.z, size
                vertex[5] = particle.startR + (particle.endR - particle.startR) * progress
                vertex[6] = particle.startG + (particle.endG - particle.startG) * progress
                vertex[7] = particle.startB + (particle.endB - particle.startB) * progress
                vertex[8] = particle.startA + (particle.endA - particle.startA) * progress
                vertex[9] = particle.rotation
            else
                self.culled = self.culled + 1
            end
        end
    end
    self.visible = visible
    if visible > 0 then self.instanceMesh:setVertices(self.instanceVertices, 1, visible) end
end

function ParticleSystem:draw(camera, environment)
    self:buildVisible(camera)
    if self.visible == 0 then return end
    local forwardX = camera.target.x - camera.position.x
    local forwardY = camera.target.y - camera.position.y
    local forwardZ = camera.target.z - camera.position.z
    local forwardLength = math.sqrt(forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ)
    forwardX, forwardY, forwardZ = forwardX / forwardLength, forwardY / forwardLength, forwardZ / forwardLength
    local rightX, rightZ = forwardZ, -forwardX
    local rightLength = math.sqrt(rightX * rightX + rightZ * rightZ)
    rightX, rightZ = rightX / rightLength, rightZ / rightLength
    local upX = -rightZ * forwardY
    local upY = rightZ * forwardX - rightX * forwardZ
    local upZ = rightX * forwardY

    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setDepthMode(self.depthMode, false)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(self.shader)
    self.shader:send("u_viewProj", "column", camera:getViewProjection())
    self.shader:send("u_cameraPos", { camera.position.x, camera.position.y, camera.position.z })
    self.shader:send("u_cameraRight", { rightX, 0, rightZ })
    self.shader:send("u_cameraUp", { upX, upY, upZ })
    self.shader:send("u_fogColor", { environment.horizon[1], environment.horizon[2], environment.horizon[3] })
    self.shader:send("u_fogStart", environment.fogStart)
    self.shader:send("u_fogDensity", environment.fogDensity)
    love.graphics.drawInstanced(self.mesh, self.visible)
    love.graphics.setMeshCullMode("back")
end

function ParticleSystem:release()
    if self.mesh then self.mesh:release(); self.mesh = nil end
    if self.instanceMesh then self.instanceMesh:release(); self.instanceMesh = nil end
end

return ParticleSystem
