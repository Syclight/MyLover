-- 通用持久地表弹坑批次：固定低模圆盘 + GPU 实例化，适合弹着/爆炸等稀疏事件。
local CraterDecals = {}
CraterDecals.__index = CraterDecals

local BASE_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}
local INSTANCE_FORMAT = {
    { "InstanceCenterScale", "float", 4 },
    { "InstanceShape", "float", 4 },
}

local function zeroVertex()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function makeDiscVertices()
    local vertices = {}
    local rings = {
        { radius = 0.00, height = 0.004 },
        { radius = 0.42, height = 0.006 },
        { radius = 0.76, height = 0.014 },
        { radius = 1.00, height = 0.002 },
    }
    local segments = 12
    for ring = 1, #rings - 1 do
        local inner, outer = rings[ring], rings[ring + 1]
        for segment = 0, segments - 1 do
            local a = segment / segments * math.pi * 2
            local b = (segment + 1) / segments * math.pi * 2
            local function point(definition, angle, segmentIndex)
                local wobble = 0.88 + math.sin(segmentIndex * 2.71 + ring * 1.83) * 0.09
                    + math.cos(segmentIndex * 5.19 - ring) * 0.035
                local x = math.cos(angle) * definition.radius * wobble
                local z = math.sin(angle) * definition.radius * wobble
                return { x, definition.height, z, x * 0.5 + 0.5, z * 0.5 + 0.5 }
            end
            local ia, ib = point(inner, a, segment), point(inner, b, segment + 1)
            local oa, ob = point(outer, a, segment), point(outer, b, segment + 1)
            vertices[#vertices + 1] = ia; vertices[#vertices + 1] = ob; vertices[#vertices + 1] = ib
            vertices[#vertices + 1] = ia; vertices[#vertices + 1] = oa; vertices[#vertices + 1] = ob
        end
    end
    return vertices
end

function CraterDecals.new(texture, shader, capacity)
    assert(love.graphics.getSupported().instancing, "CraterDecals requires GPU instancing")
    local self = setmetatable({
        texture = assert(texture, "CraterDecals requires a dirt texture"),
        shader = assert(shader, "CraterDecals requires a shader"),
        capacity = capacity or 160,
        decals = {},
        vertices = {},
        visible = 0,
    }, CraterDecals)
    for index = 1, self.capacity do self.vertices[index] = zeroVertex() end
    self.instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, self.vertices, "points", "dynamic")
    self.mesh = love.graphics.newMesh(BASE_FORMAT, makeDiscVertices(), "triangles", "static")
    self.mesh:attachAttribute("InstanceCenterScale", self.instanceMesh, "perinstance")
    self.mesh:attachAttribute("InstanceShape", self.instanceMesh, "perinstance")
    return self
end

function CraterDecals:append(item)
    if #self.decals >= self.capacity then table.remove(self.decals, 1) end
    self.decals[#self.decals + 1] = item
end

function CraterDecals:add(x, z, seed, facing)
    local direction = facing and (facing >= 0 and 0 or math.pi) or (seed or 0) * math.pi * 2
    local angle = direction + math.sin((seed or 0) * 71.3) * 0.19
    local baseRadius = 0.23 + (seed or 0) * 0.055
    self:append({
        x = x, y = 0.021, z = z,
        radiusX = baseRadius * 1.34, radiusZ = baseRadius * 0.72,
        angle = angle, seed = (seed or 0) * 0.71 + 0.13, strength = 1.0,
    })
    self:append({
        x = x - math.cos(angle) * baseRadius * 0.68, y = 0.020, z = z - math.sin(angle) * baseRadius * 0.68,
        radiusX = baseRadius * 1.12, radiusZ = baseRadius * 0.26,
        angle = angle, seed = (seed or 0) * 0.41 + 0.49, strength = 0.58,
    })
end

function CraterDecals:clear()
    self.decals = {}
    self.visible = 0
end

function CraterDecals:draw(camera, environment)
    local visible = 0
    for _, item in ipairs(self.decals) do
        if camera:isSphereVisible(item.x, item.y, item.z, math.max(item.radiusX, item.radiusZ)) then
            visible = visible + 1
            local vertex = self.vertices[visible]
            vertex[1], vertex[2], vertex[3], vertex[4] = item.x, item.y, item.z, item.radiusX
            vertex[5], vertex[6], vertex[7], vertex[8] = item.radiusZ, item.angle, item.seed, item.strength
        end
    end
    self.visible = visible
    if visible == 0 then return end
    self.instanceMesh:setVertices(self.vertices, 1, visible)
    love.graphics.setShader(self.shader)
    self.shader:send("u_viewProj", "column", camera:getViewProjection())
    self.shader:send("u_cameraPos", { camera.position.x, camera.position.y, camera.position.z })
    self.shader:send("u_fogColor", { environment.horizon[1], environment.horizon[2], environment.horizon[3] })
    self.shader:send("u_fogStart", environment.fogStart)
    self.shader:send("u_fogDensity", environment.fogDensity)
    self.shader:send("u_dirtTexture", self.texture)
    love.graphics.setDepthMode("lequal", false)
    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.drawInstanced(self.mesh, visible)
    love.graphics.setMeshCullMode("back")
end

function CraterDecals:release()
    if self.mesh then self.mesh:release(); self.mesh = nil end
    if self.instanceMesh then self.instanceMesh:release(); self.instanceMesh = nil end
end

return CraterDecals
