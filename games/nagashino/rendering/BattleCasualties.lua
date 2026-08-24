-- 静态遗体批次：死亡图集覆盖在扁平半胶囊上；所有距离使用同一实例化网格。
local BattleCasualties = {}
BattleCasualties.__index = BattleCasualties

local BODY_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal", "float", 3 },
    { "VertexSide", "float", 1 },
}

local INSTANCE_FORMAT = {
    { "InstanceCenterScale", "float", 4 },
    { "InstanceScaleRotation", "float", 4 },
    { "InstanceUv", "float", 4 },
}

local CONTACT_BASE_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
}

local CONTACT_INSTANCE_FORMAT = {
    { "InstanceShadowCenter", "float", 4 },
    { "InstanceShadowScale", "float", 4 },
}

local FRAMES = {
    cavalry = { u0 = 0.00, u1 = 0.50, v0 = 0.00, v1 = 0.50, scaleX = 2.15, scaleZ = 1.72, bodyX = 0.96, bodyZ = 0.90 },
    ashigaru = { u0 = 0.50, u1 = 1.00, v0 = 0.00, v1 = 0.50, scaleX = 1.28, scaleZ = 1.02, bodyX = 0.95, bodyZ = 0.88 },
    teppo = { u0 = 0.00, u1 = 0.50, v0 = 0.50, v1 = 1.00, scaleX = 1.32, scaleZ = 1.06, bodyX = 0.95, bodyZ = 0.88 },
}

-- 长向 z 的半胶囊剖面；高度极低，边缘落回地面以避免可见的黑色围墙。
local CAPSULE_PROFILE = {
    { z = -0.50, halfWidth = 0.18, height = 0.008 },
    { z = -0.32, halfWidth = 0.43, height = 0.055 },
    { z = 0.00, halfWidth = 0.50, height = 0.088 },
    { z = 0.32, halfWidth = 0.43, height = 0.055 },
    { z = 0.50, halfWidth = 0.18, height = 0.008 },
}
local CAPSULE_COLUMNS = { -1.0, -0.5, 0.0, 0.5, 1.0 }

local CONTACT_VERTICES = {}
for index = 0, 11 do
    local a = index / 12 * math.pi * 2
    local b = (index + 1) / 12 * math.pi * 2
    CONTACT_VERTICES[#CONTACT_VERTICES + 1] = { 0, 0, 0, 0.5, 0.5 }
    CONTACT_VERTICES[#CONTACT_VERTICES + 1] = { math.cos(b), math.sin(b), 0, 1, 1 }
    CONTACT_VERTICES[#CONTACT_VERTICES + 1] = { math.cos(a), math.sin(a), 0, 0, 1 }
end

local function zeroVertex()
    return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function normalFor(a, b, c)
    local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local acx, acy, acz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local x = aby * acz - abz * acy
    local y = abz * acx - abx * acz
    local z = abx * acy - aby * acx
    local length = math.sqrt(x * x + y * y + z * z)
    if length < 1e-8 then return { 0, 1, 0 } end
    return { x / length, y / length, z / length }
end

local function vertex(point, u, v, normal, side)
    return { point[1], point[2], point[3], u, v, normal[1], normal[2], normal[3], side }
end

local function appendTriangle(vertices, a, b, c, au, av, bu, bv, cu, cv, side)
    local normal = normalFor(a, b, c)
    vertices[#vertices + 1] = vertex(a, au, av, normal, side)
    vertices[#vertices + 1] = vertex(b, bu, bv, normal, side)
    vertices[#vertices + 1] = vertex(c, cu, cv, normal, side)
end

local function makeCapsuleVertices()
    local vertices, grid = {}, {}
    for rowIndex, profile in ipairs(CAPSULE_PROFILE) do
        grid[rowIndex] = {}
        for columnIndex, ratio in ipairs(CAPSULE_COLUMNS) do
            local curve = math.sqrt(math.max(0, 1 - ratio * ratio))
            grid[rowIndex][columnIndex] = {
                point = { profile.halfWidth * ratio, profile.height * curve, profile.z },
                u = ratio * 0.5 + 0.5,
                v = 0.5 - profile.z,
            }
        end
    end
    for row = 1, #CAPSULE_PROFILE - 1 do
        for column = 1, #CAPSULE_COLUMNS - 1 do
            local a, b = grid[row][column], grid[row][column + 1]
            local c, d = grid[row + 1][column], grid[row + 1][column + 1]
            appendTriangle(vertices, a.point, d.point, b.point, a.u, a.v, d.u, d.v, b.u, b.v, 0)
            appendTriangle(vertices, a.point, c.point, d.point, a.u, a.v, c.u, c.v, d.u, d.v, 0)
        end
    end
    -- 前后封口极薄，使用扩展颜色而不是黑色，且不会在长边形成边框。
    for _, row in ipairs({ 1, #CAPSULE_PROFILE }) do
        for column = 1, #CAPSULE_COLUMNS - 1 do
            local a, b = grid[row][column], grid[row][column + 1]
            local bottomA = { a.point[1], 0, a.point[3] }
            local bottomB = { b.point[1], 0, b.point[3] }
            appendTriangle(vertices, a.point, bottomB, b.point, a.u, a.v, b.u, b.v, b.u, b.v, 1)
            appendTriangle(vertices, a.point, bottomA, bottomB, a.u, a.v, a.u, a.v, b.u, b.v, 1)
        end
    end
    return vertices
end

local function makeBodyBatch(texture, capacity)
    local vertices = {}
    local contactVertices = {}
    for index = 1, capacity do vertices[index] = zeroVertex() end
    for index = 1, capacity do contactVertices[index] = { 0, 0, 0, 0, 0, 0, 0, 0 } end
    local instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, vertices, "points", "dynamic")
    local mesh = love.graphics.newMesh(BODY_FORMAT, makeCapsuleVertices(), "triangles", "static")
    local contactInstanceMesh = love.graphics.newMesh(CONTACT_INSTANCE_FORMAT, contactVertices, "points", "dynamic")
    local contactMesh = love.graphics.newMesh(CONTACT_BASE_FORMAT, CONTACT_VERTICES, "triangles", "static")
    mesh:setTexture(texture)
    mesh:attachAttribute("InstanceCenterScale", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceScaleRotation", instanceMesh, "perinstance")
    mesh:attachAttribute("InstanceUv", instanceMesh, "perinstance")
    contactMesh:attachAttribute("InstanceShadowCenter", contactInstanceMesh, "perinstance")
    contactMesh:attachAttribute("InstanceShadowScale", contactInstanceMesh, "perinstance")
    return {
        mesh = mesh, instanceMesh = instanceMesh, vertices = vertices,
        contactMesh = contactMesh, contactInstanceMesh = contactInstanceMesh, contactVertices = contactVertices,
        visible = 0,
    }
end

function BattleCasualties.new(texture, edgeTexture, shader, contactShader, capacity)
    assert(love.graphics.getSupported().instancing, "BattleCasualties requires GPU instancing")
    local self = setmetatable({
        texture = assert(texture, "BattleCasualties requires a death atlas"),
        edgeTexture = assert(edgeTexture, "BattleCasualties requires an edge texture"),
        shader = assert(shader, "BattleCasualties requires a body shader"),
        contactShader = assert(contactShader, "BattleCasualties requires a contact shadow shader"),
        capacity = capacity or 96,
        casualties = {},
        visible = 0,
        nearVisible = 0,
        culled = 0,
    }, BattleCasualties)
    self.bodies = {
        cavalry = makeBodyBatch(self.texture, self.capacity),
        ashigaru = makeBodyBatch(self.texture, self.capacity),
        teppo = makeBodyBatch(self.texture, self.capacity),
    }
    return self
end

function BattleCasualties:add(event)
    if #self.casualties >= self.capacity then return end
    local frame = FRAMES[event.role] or FRAMES.ashigaru
    self.casualties[#self.casualties + 1] = {
        x = event.x, y = 0.072, z = event.z,
        angle = (event.seed or 0) * math.pi * 2 + (event.facing or 0) * 0.24,
        frame = frame, role = event.role or "ashigaru", age = 0,
    }
end

function BattleCasualties:update(dt)
    for _, casualty in ipairs(self.casualties) do casualty.age = casualty.age + dt end
end

function BattleCasualties:clear()
    self.casualties = {}
    self.visible, self.nearVisible, self.culled = 0, 0, 0
end

function BattleCasualties:buildVisible(camera)
    local visible = 0
    self.culled = 0
    for _, batch in pairs(self.bodies) do batch.visible = 0 end
    for _, casualty in ipairs(self.casualties) do
        local frame = casualty.frame
        if camera:isSphereVisible(casualty.x, casualty.y, casualty.z, math.max(frame.scaleX, frame.scaleZ)) then
            local batch = self.bodies[casualty.role] or self.bodies.ashigaru
            batch.visible = batch.visible + 1
            local vertex = batch.vertices[batch.visible]
            local settle = math.min(1, casualty.age / 0.28)
            local scale = 0.58 + settle * 0.42
            vertex[1], vertex[2], vertex[3], vertex[4] = casualty.x, casualty.y + 0.004, casualty.z,
                frame.scaleX * frame.bodyX * scale
            vertex[5], vertex[6], vertex[7], vertex[8] = frame.scaleZ * frame.bodyZ * scale,
                casualty.angle, frame.u0, frame.u1
            vertex[9], vertex[10], vertex[11], vertex[12] = frame.v0, frame.v1, 0, 0
            local contact = batch.contactVertices[batch.visible]
            local contactScale = casualty.role == "cavalry" and 0.82 or 0.52
            contact[1], contact[2], contact[3], contact[4] = casualty.x, 0.012, casualty.z,
                frame.scaleX * contactScale * scale
            contact[5], contact[6], contact[7], contact[8] = frame.scaleZ * contactScale * scale,
                0.16 + settle * 0.08, 0, 0
            visible = visible + 1
        else
            self.culled = self.culled + 1
        end
    end
    self.visible, self.nearVisible = visible, visible
    for _, batch in pairs(self.bodies) do
        if batch.visible > 0 then
            batch.instanceMesh:setVertices(batch.vertices, 1, batch.visible)
            batch.contactInstanceMesh:setVertices(batch.contactVertices, 1, batch.visible)
        end
    end
end

function BattleCasualties:draw3D(camera, environment)
    self:buildVisible(camera)
    if self.visible == 0 then return end
    love.graphics.setShader(self.contactShader)
    self.contactShader:send("u_viewProj", "column", camera:getViewProjection())
    love.graphics.setDepthMode("lequal", false)
    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    for _, batch in pairs(self.bodies) do
        if batch.visible > 0 then love.graphics.drawInstanced(batch.contactMesh, batch.visible) end
    end

    love.graphics.setShader(self.shader)
    self.shader:send("u_viewProj", "column", camera:getViewProjection())
    self.shader:send("u_cameraPos", { camera.position.x, camera.position.y, camera.position.z })
    self.shader:send("u_lightDir", { environment.lightDir.x, environment.lightDir.y, environment.lightDir.z })
    self.shader:send("u_fogColor", { environment.horizon[1], environment.horizon[2], environment.horizon[3] })
    self.shader:send("u_fogStart", environment.fogStart)
    self.shader:send("u_fogDensity", environment.fogDensity)
    self.shader:send("u_edgeTexture", self.edgeTexture)
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setMeshCullMode("none")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    for _, batch in pairs(self.bodies) do
        if batch.visible > 0 then love.graphics.drawInstanced(batch.mesh, batch.visible) end
    end
    love.graphics.setMeshCullMode("back")
end

function BattleCasualties:release()
    for _, batch in pairs(self.bodies or {}) do
        batch.mesh:release()
        batch.instanceMesh:release()
        batch.contactMesh:release()
        batch.contactInstanceMesh:release()
    end
    self.bodies = nil
end

return BattleCasualties
