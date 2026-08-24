-- 遗体着地后抛下的轻量武器批次；所有物件共用一张静态盒网格和一份实例缓冲。
local DroppedWeapons = {}
DroppedWeapons.__index = DroppedWeapons

local BASE_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal", "float", 3 },
}

local INSTANCE_FORMAT = {
    { "InstanceCenterLength", "float", 4 },
    { "InstanceWeaponShape", "float", 4 },
}

local function face(vertices, a, b, c, d, normal)
    vertices[#vertices + 1] = { a[1], a[2], a[3], 0, 1, normal[1], normal[2], normal[3] }
    vertices[#vertices + 1] = { b[1], b[2], b[3], 1, 1, normal[1], normal[2], normal[3] }
    vertices[#vertices + 1] = { c[1], c[2], c[3], 1, 0, normal[1], normal[2], normal[3] }
    vertices[#vertices + 1] = { a[1], a[2], a[3], 0, 1, normal[1], normal[2], normal[3] }
    vertices[#vertices + 1] = { c[1], c[2], c[3], 1, 0, normal[1], normal[2], normal[3] }
    vertices[#vertices + 1] = { d[1], d[2], d[3], 0, 0, normal[1], normal[2], normal[3] }
end

local function makeBox()
    local x0, x1, y0, y1, z0, z1 = -0.5, 0.5, 0, 0.052, -0.5, 0.5
    local vertices = {}
    face(vertices, { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 }, { 0, 1, 0 })
    face(vertices, { x0, y0, z0 }, { x0, y0, z1 }, { x1, y0, z1 }, { x1, y0, z0 }, { 0, -1, 0 })
    face(vertices, { x0, y0, z1 }, { x0, y1, z1 }, { x1, y1, z1 }, { x1, y0, z1 }, { 0, 0, 1 })
    face(vertices, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 }, { x0, y0, z0 }, { 0, 0, -1 })
    face(vertices, { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, { x0, y0, z1 }, { -1, 0, 0 })
    face(vertices, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x1, y0, z0 }, { 1, 0, 0 })
    return vertices
end

local function zeroVertex()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

function DroppedWeapons.new(shader, capacity)
    assert(love.graphics.getSupported().instancing, "DroppedWeapons requires GPU instancing")
    local self = setmetatable({
        shader = assert(shader, "DroppedWeapons requires a shader"),
        capacity = capacity or 96,
        weapons = {}, visible = 0, culled = 0,
    }, DroppedWeapons)
    self.vertices = {}
    for index = 1, self.capacity do self.vertices[index] = zeroVertex() end
    self.instanceMesh = love.graphics.newMesh(INSTANCE_FORMAT, self.vertices, "points", "dynamic")
    self.mesh = love.graphics.newMesh(BASE_FORMAT, makeBox(), "triangles", "static")
    self.mesh:attachAttribute("InstanceCenterLength", self.instanceMesh, "perinstance")
    self.mesh:attachAttribute("InstanceWeaponShape", self.instanceMesh, "perinstance")
    return self
end

function DroppedWeapons:add(event)
    if #self.weapons >= self.capacity then return end
    local angle = (event.facing or 1) >= 0 and 0 or math.pi
    angle = angle + (event.seed or 0) * 1.35 - 0.68
    self.weapons[#self.weapons + 1] = {
        x = event.x - math.sin(angle) * 0.23,
        z = event.z + math.cos(angle) * 0.23,
        angle = angle,
        seed = event.seed or 0,
        role = event.role or "ashigaru",
        age = 0,
    }
end

function DroppedWeapons:update(dt)
    for _, weapon in ipairs(self.weapons) do weapon.age = weapon.age + dt end
end

function DroppedWeapons:clear()
    self.weapons = {}
    self.visible, self.culled = 0, 0
end

function DroppedWeapons:draw(camera, environment)
    local visible = 0
    self.culled = 0
    for _, weapon in ipairs(self.weapons) do
        if camera:isSphereVisible(weapon.x, 0.16, weapon.z, 0.75) then
            visible = visible + 1
            local vertex = self.vertices[visible]
            local settle = math.min(1, weapon.age / 0.20)
            local length, width, kind = 0.92, 0.044, 1
            if weapon.role == "cavalry" then length, width, kind = 0.68, 0.070, 0
            elseif weapon.role == "teppo" then length, width, kind = 0.76, 0.090, 2 end
            vertex[1], vertex[2], vertex[3], vertex[4] = weapon.x, 0.024 + (1 - settle) * 0.17, weapon.z, length
            vertex[5], vertex[6], vertex[7], vertex[8] = width,
                weapon.angle + (1 - settle) * (weapon.seed - 0.5) * 0.80, kind, settle
        else
            self.culled = self.culled + 1
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
    love.graphics.setDepthMode("lequal", true)
    love.graphics.setMeshCullMode("back")
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.drawInstanced(self.mesh, visible)
end

function DroppedWeapons:release()
    self.mesh:release()
    self.instanceMesh:release()
end

return DroppedWeapons
