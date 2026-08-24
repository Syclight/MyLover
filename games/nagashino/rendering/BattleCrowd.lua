-- GPU 实例化 HD-2D 人群：静态四边形 + 每单位实例数据，避免每帧重建整套顶点。
local BattleCrowd = {}
BattleCrowd.__index = BattleCrowd

local BASE_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}

local INSTANCE_FORMAT = {
    { "InstanceCenter", "float", 4 },
    { "InstanceRightSize", "float", 4 },
    { "InstanceUv", "float", 4 },
}

local SHADOW_INSTANCE_FORMAT = {
    { "InstanceShadowCenter", "float", 4 },
    { "InstanceShadowScale", "float", 4 },
}

local QUAD_VERTICES = {
    { -1, 0, 0, 0, 1 }, { 1, 0, 0, 1, 1 }, { 1, 1, 0, 1, 0 },
    { -1, 0, 0, 0, 1 }, { 1, 1, 0, 1, 0 }, { -1, 1, 0, 0, 0 },
}

local SHADOW_VERTICES = {}
for index = 0, 7 do
    local a = index / 8 * math.pi * 2
    local b = (index + 1) / 8 * math.pi * 2
    SHADOW_VERTICES[#SHADOW_VERTICES + 1] = { 0, 0, 0, 0.5, 0.5 }
    SHADOW_VERTICES[#SHADOW_VERTICES + 1] = { math.cos(b), math.sin(b), 0, 1, 1 }
    SHADOW_VERTICES[#SHADOW_VERTICES + 1] = { math.cos(a), math.sin(a), 0, 0, 1 }
end

local COLORS = {
    oda = { 0.96, 0.96, 0.98, 1 },
    tokugawa = { 0.80, 0.90, 1.00, 1 },
    takeda = { 1.00, 1.00, 1.00, 1 },
}

local ROLE_SPECS = {
    cavalry = {
        sheet = "cavalry", deathSheet = "cavalryDeath", halfWidth = 0.84, height = 1.62, shadowX = 0.68, shadowZ = 0.30,
        deathHalfWidth = 1.02, deathHeight = 1.74,
        frames = { { 0.138, 0.839 }, { 0.138, 0.848 }, { 0.138, 0.859 }, { 0.138, 0.837 } },
    },
    ashigaru = {
        sheet = "ashigaru", halfWidth = 0.50, height = 1.60, shadowX = 0.40, shadowZ = 0.20,
        frames = { { 0.166, 0.784 }, { 0.196, 0.780 }, { 0.165, 0.784 }, { 0.201, 0.790 } },
    },
    teppo = {
        sheet = "teppo", halfWidth = 0.52, height = 1.60, shadowX = 0.42, shadowZ = 0.21,
        frames = { { 0.085, 0.884 }, { 0.085, 0.884 }, { 0.085, 0.884 }, { 0.082, 0.884 } },
    },
}

local ANIMATION_DISTANCE = 36

local function zeroVertex(count)
    local vertex = {}
    for index = 1, count do vertex[index] = 0 end
    return vertex
end

local function frameFor(unit, battleTime, phase)
    if unit.dying then return 0 end
    if unit.role == "cavalry" then
        local framesPerSecond = math.max(1.5, math.min(10, unit.speed * 2.1))
        return math.floor(battleTime * framesPerSecond + unit.seed * 4) % 4
    end
    if unit.role == "ashigaru" then
        return math.floor(battleTime * 3.2 + unit.seed * 4) % 4
    end
    if phase == "deployment" then return 0 end

    local volleyTime = (battleTime + unit.seed * 0.08) * 2.0
    local activeRank = math.floor(volleyTime) % 3
    if unit.volleyRank ~= activeRank then return 0 end
    local beat = volleyTime % 1
    if beat < 0.22 then return 1 end
    if beat < 0.32 then return 2 end
    if beat < 0.80 then return 3 end
    return 0
end

local function attachSpriteAttributes(mesh, instanceMesh)
    mesh:attachAttribute("InstanceCenter", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceRightSize", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceUv", instanceMesh, "perinstance")
end

local function attachShadowAttributes(mesh, instanceMesh)
    mesh:attachAttribute("InstanceShadowCenter", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceShadowScale", instanceMesh, "perinstance")
end

local function writeInstance(vertex, shadowVertex, unit, camera, battleTime, phase, spec, distance)
    local toCameraX = camera.position.x - unit.x
    local toCameraZ = camera.position.z - unit.z
    local horizontalDistance = math.sqrt(toCameraX * toCameraX + toCameraZ * toCameraZ)
    if horizontalDistance < 0.001 then horizontalDistance = 1 end
    local normalX, normalZ = toCameraX / horizontalDistance, toCameraZ / horizontalDistance
    local rightX, rightZ = normalZ, -normalX
    local frame = distance > ANIMATION_DISTANCE and 0 or frameFor(unit, battleTime, phase)
    local frameBounds = spec.frames[frame + 1]
    local padding = 0.0025
    local u0 = frame * 0.25 + padding
    local u1 = (frame + 1) * 0.25 - padding
    if unit.facing * normalZ > 0 then u0, u1 = u1, u0 end

    vertex[1], vertex[2], vertex[3], vertex[4] = unit.x, 0.035, unit.z, 0
    vertex[5], vertex[6], vertex[7], vertex[8] = rightX, rightZ,
        spec.halfWidth, spec.height
    vertex[9], vertex[10], vertex[11], vertex[12] = u0, u1, frameBounds[1], frameBounds[2]

    shadowVertex[1], shadowVertex[2], shadowVertex[3], shadowVertex[4] = unit.x, 0.018, unit.z,
        spec.shadowX
    shadowVertex[5], shadowVertex[6], shadowVertex[7], shadowVertex[8] = spec.shadowZ,
        distance > ANIMATION_DISTANCE and 0.24 or 0.42, 0, 0
end

local function writeDeathShadow(shadowVertex, unit, spec, distance)
    shadowVertex[1], shadowVertex[2], shadowVertex[3], shadowVertex[4] = unit.x, 0.018, unit.z,
        spec.shadowX
    shadowVertex[5], shadowVertex[6], shadowVertex[7], shadowVertex[8] = spec.shadowZ,
        distance > ANIMATION_DISTANCE and 0.24 or 0.42, 0, 0
end

local function writeDeathInstance(vertex, unit, camera, spec)
    local toCameraX = camera.position.x - unit.x
    local toCameraZ = camera.position.z - unit.z
    local horizontalDistance = math.sqrt(toCameraX * toCameraX + toCameraZ * toCameraZ)
    if horizontalDistance < 0.001 then horizontalDistance = 1 end
    local normalZ = toCameraZ / horizontalDistance
    local rightX, rightZ = normalZ, -toCameraX / horizontalDistance
    local frame = math.min(4, math.floor((unit.fallProgress or 0) * 5))
    local padding = 0.0015
    local u0 = frame * 0.20 + padding
    local u1 = (frame + 1) * 0.20 - padding
    if unit.facing * normalZ > 0 then u0, u1 = u1, u0 end
    vertex[1], vertex[2], vertex[3], vertex[4] = unit.x, 0.035, unit.z, 0
    vertex[5], vertex[6], vertex[7], vertex[8] = rightX, rightZ, spec.deathHalfWidth, spec.deathHeight
    vertex[9], vertex[10], vertex[11], vertex[12] = u0, u1, padding, 1 - padding
end

function BattleCrowd.new(simulation, spriteSheets, shaders)
    assert(love.graphics.getSupported().instancing, "Nagashino crowd renderer requires GPU instancing")
    local self = setmetatable({
        simulation = simulation,
        spriteShader = assert(shaders.sprite, "missing crowd sprite shader"),
        shadowShader = assert(shaders.shadow, "missing crowd shadow shader"),
        batches = {},
        visible = 0,
        culled = 0,
    }, BattleCrowd)
    local byKey = {}
    for _, unit in ipairs(simulation.units) do
        local key = unit.faction .. "_" .. unit.role
        local batch = byKey[key]
        if not batch then
            local spec = ROLE_SPECS[unit.role]
            batch = {
                key = key, units = {}, spec = spec, spriteImage = spriteSheets[spec.sheet],
                deathSpriteImage = spec.deathSheet and spriteSheets[spec.deathSheet], color = COLORS[unit.faction],
            }
            byKey[key] = batch
            self.batches[#self.batches + 1] = batch
        end
        batch.units[#batch.units + 1] = unit
    end

    for _, batch in ipairs(self.batches) do
        batch.instanceVertices, batch.deathVertices, batch.shadowVertices = {}, {}, {}
        for index = 1, #batch.units do
            batch.instanceVertices[index] = zeroVertex(12)
            batch.deathVertices[index] = zeroVertex(12)
            batch.shadowVertices[index] = zeroVertex(8)
        end
        batch.instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, batch.instanceVertices, "points", "dynamic")
        batch.deathInstanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, batch.deathVertices, "points", "dynamic")
        batch.shadowInstanceMesh = love.graphics.newMesh(SHADOW_INSTANCE_FORMAT, batch.shadowVertices, "points", "dynamic")
        batch.spriteMesh = love.graphics.newMesh(BASE_FORMAT, QUAD_VERTICES, "triangles", "static")
        batch.spriteMesh:setTexture(batch.spriteImage)
        batch.deathMesh = love.graphics.newMesh(BASE_FORMAT, QUAD_VERTICES, "triangles", "static")
        if batch.deathSpriteImage then batch.deathMesh:setTexture(batch.deathSpriteImage) end
        batch.shadowMesh = love.graphics.newMesh(BASE_FORMAT, SHADOW_VERTICES, "triangles", "static")
        attachSpriteAttributes(batch.spriteMesh, batch.instanceMesh)
        attachSpriteAttributes(batch.deathMesh, batch.deathInstanceMesh)
        attachShadowAttributes(batch.shadowMesh, batch.shadowInstanceMesh)
        batch.visible, batch.deathVisible, batch.shadowVisible = 0, 0, 0
    end
    return self
end

function BattleCrowd:reset(simulation)
    self.simulation = simulation or self.simulation
    local grouped = {}
    for _, unit in ipairs(self.simulation.units) do
        local key = unit.faction .. "_" .. unit.role
        local units = grouped[key]
        if not units then
            units = {}
            grouped[key] = units
        end
        units[#units + 1] = unit
    end
    self.visible, self.culled = 0, 0
    for _, batch in ipairs(self.batches) do
        local units = grouped[batch.key] or {}
        assert(#units <= #batch.instanceVertices, "BattleCrowd reset exceeds batch capacity")
        batch.units = units
        batch.visible, batch.deathVisible, batch.shadowVisible = 0, 0, 0
    end
end

function BattleCrowd:update(camera, battleTime)
    local phase = self.simulation.phase
    self.visible, self.culled = 0, 0
    for _, batch in ipairs(self.batches) do
        local visible, deathVisible, shadowVisible = 0, 0, 0
        local radius = math.max(batch.spec.halfWidth, batch.spec.height * 0.5)
        for _, unit in ipairs(batch.units) do
            if (unit.alive or unit.dying) and camera:isSphereVisible(unit.x, batch.spec.height * 0.5, unit.z, radius) then
                shadowVisible = shadowVisible + 1
                local dx = camera.position.x - unit.x
                local dy = camera.position.y - batch.spec.height * 0.5
                local dz = camera.position.z - unit.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                if unit.dying and batch.deathSpriteImage then
                    deathVisible = deathVisible + 1
                    writeDeathInstance(batch.deathVertices[deathVisible], unit, camera, batch.spec)
                    writeDeathShadow(batch.shadowVertices[shadowVisible], unit, batch.spec, distance)
                else
                    visible = visible + 1
                    writeInstance(batch.instanceVertices[visible], batch.shadowVertices[shadowVisible], unit,
                        camera, battleTime, phase, batch.spec, distance)
                end
            else
                self.culled = self.culled + 1
            end
        end
        batch.visible, batch.deathVisible, batch.shadowVisible = visible, deathVisible, shadowVisible
        self.visible = self.visible + visible + deathVisible
        if visible > 0 then
            batch.instanceMesh:setVertices(batch.instanceVertices, 1, visible)
        end
        if deathVisible > 0 then batch.deathInstanceMesh:setVertices(batch.deathVertices, 1, deathVisible) end
        if shadowVisible > 0 then batch.shadowInstanceMesh:setVertices(batch.shadowVertices, 1, shadowVisible) end
    end
end

function BattleCrowd:draw(camera, environment)
    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setShader(self.shadowShader)
    self.shadowShader:send("u_viewProj", "column", camera:getViewProjection())
    love.graphics.setDepthMode("lequal", false)
    for _, batch in ipairs(self.batches) do
        if batch.shadowVisible > 0 then love.graphics.drawInstanced(batch.shadowMesh, batch.shadowVisible) end
    end

    love.graphics.setShader(self.spriteShader)
    self.spriteShader:send("u_viewProj", "column", camera:getViewProjection())
    self.spriteShader:send("u_cameraPos", { camera.position.x, camera.position.y, camera.position.z })
    self.spriteShader:send("u_fogColor", { environment.horizon[1], environment.horizon[2], environment.horizon[3] })
    self.spriteShader:send("u_fogStart", environment.fogStart)
    self.spriteShader:send("u_fogDensity", environment.fogDensity)
    love.graphics.setDepthMode("lequal", true)
    for _, batch in ipairs(self.batches) do
        if batch.visible > 0 then
            self.spriteShader:send("u_tint", batch.color)
            love.graphics.drawInstanced(batch.spriteMesh, batch.visible)
        end
        if batch.deathVisible > 0 then
            self.spriteShader:send("u_tint", batch.color)
            love.graphics.drawInstanced(batch.deathMesh, batch.deathVisible)
        end
    end
    love.graphics.setMeshCullMode("back")
end

function BattleCrowd:release()
    for _, batch in ipairs(self.batches) do
        batch.spriteMesh:release()
        batch.shadowMesh:release()
        batch.instanceMesh:release()
        batch.deathMesh:release()
        batch.deathInstanceMesh:release()
        batch.shadowInstanceMesh:release()
    end
end

return BattleCrowd
