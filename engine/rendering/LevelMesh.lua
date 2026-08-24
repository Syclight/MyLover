-- 关卡级静态网格：一个 Mesh + 对象表 + material 表。
--
-- MeshBin/ObjLoader 已把 Blender OBJ 的 o/g/usemtl 转成对象段：
--   { name, material, indexStart, indexCount, center, boundingRadius }
-- LevelMesh 在运行时按对象段 setDrawRange，实现分对象视锥剔除与材质绑定。
local Mat4 = require("engine.math.Mat4")
local MeshBin = require("engine.rendering.MeshBin")
local ObjLoader = require("engine.rendering.ObjLoader")
local Fuc = require("engine.utils.Fuc")

local LevelMesh = {}
LevelMesh.__index = LevelMesh

local DEFAULT_MATERIAL = {
    color = { 1, 1, 1, 1 },
    metallic = 0,
    roughness = 0.75,
    ao = 1,
    normalScale = 1,
}

local DEFAULT_OPTIONS = {
    skipSuffixes = { "_col", "_trigger" },
    skipNames = {},
    skipPrefixes = {},
    colliderSuffix = "_col",
    triggerSuffix = "_trigger",
}

local function fallbackObjects(header)
    return {
        {
            name = "default",
            material = "default",
            indexStart = 1,
            indexCount = header.indexCount or 0,
            center = { 0, 0, 0 },
            boundingRadius = header.boundingRadius or 0,
        },
    }
end

local function maxAxisScale(model)
    local sx = math.sqrt(model[1] * model[1] + model[2] * model[2] + model[3] * model[3])
    local sy = math.sqrt(model[5] * model[5] + model[6] * model[6] + model[7] * model[7])
    local sz = math.sqrt(model[9] * model[9] + model[10] * model[10] + model[11] * model[11])
    return math.max(sx, sy, sz)
end

local function materialColor(material)
    return material and material.color or DEFAULT_MATERIAL.color
end

local function hasSuffix(value, suffix)
    return type(value) == "string" and value:sub(-#suffix) == suffix
end

local function hasPrefix(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function mergeOptions(options)
    local merged = {}
    for key, value in pairs(DEFAULT_OPTIONS) do merged[key] = value end
    for key, value in pairs(options or {}) do merged[key] = value end
    return merged
end

local function shouldRenderObject(object, options)
    local name = object.name or ""
    for _, skippedName in ipairs(options.skipNames or {}) do
        if name == skippedName then return false end
    end
    for _, prefix in ipairs(options.skipPrefixes or {}) do
        if hasPrefix(name, prefix) then return false end
    end
    for _, suffix in ipairs(options.skipSuffixes or {}) do
        if hasSuffix(name, suffix) then return false end
    end
    return true
end

local function cloneMaterial(material)
    local copy = {}
    for key, value in pairs(material or {}) do copy[key] = value end
    return copy
end

local function resolveTexture(value, resolver)
    if type(value) ~= "string" then return value end
    return resolver and resolver(value) or value
end

local function compileMaterials(defs, resolver)
    local materials = {}
    for name, def in pairs(defs or {}) do
        local material = cloneMaterial(def)
        material.albedoTexture = resolveTexture(material.albedoTexture or material.texture or material.albedo, resolver)
        material.texture = material.albedoTexture
        material.normalTexture = resolveTexture(material.normalTexture or material.normalMap or material.normal, resolver)
        material.pbrTexture = resolveTexture(material.pbrTexture or material.pbrMap or material.pbr, resolver)
        material.roughnessTexture = resolveTexture(material.roughnessTexture or material.roughnessMap, resolver)
        material.aoTexture = resolveTexture(material.aoTexture or material.aoMap, resolver)
        material.alphaMaskTexture = resolveTexture(material.alphaMaskTexture or material.alphaMask, resolver)
        materials[name] = material
    end
    return materials
end

local function resourceResolver(resourceManager)
    return function(name)
        return resourceManager and resourceManager:get(name) or nil
    end
end

local function loadManifestModule(path)
    return require(path:gsub("%.lua$", ""))
end

function LevelMesh.objectRole(name, options)
    options = mergeOptions(options)
    if hasSuffix(name, options.colliderSuffix) then return "collider" end
    if hasSuffix(name, options.triggerSuffix) then return "trigger" end
    return "render"
end

function LevelMesh.compileMaterials(defs, resolver)
    return compileMaterials(defs, resolver)
end

function LevelMesh.new(mesh, header, materials, options)
    assert(mesh, "LevelMesh.new requires a Mesh")
    header = header or {}
    local self = setmetatable({}, LevelMesh)
    self.mesh = mesh
    self.header = header
    self.options = mergeOptions(options)
    self.allObjects = (#(header.objects or {}) > 0) and header.objects or fallbackObjects(header)
    self.objects = {}
    self.colliders = {}
    self.triggers = {}
    for _, object in ipairs(self.allObjects) do
        local role = LevelMesh.objectRole(object.name, self.options)
        object.role = role
        if role == "collider" then
            self.colliders[#self.colliders + 1] = object
        elseif role == "trigger" then
            self.triggers[#self.triggers + 1] = object
        end
        if role == "render" and shouldRenderObject(object, self.options) then
            self.objects[#self.objects + 1] = object
        end
    end
    self.materials = materials or {}
    self.defaultMaterial = self.materials.default or DEFAULT_MATERIAL
    self._identity = Mat4.new()
    return self
end

function LevelMesh.loadMeshBin(path, texture, materials, options)
    local mesh, header = MeshBin.load(path, texture)
    return LevelMesh.new(mesh, header, materials, options)
end

function LevelMesh.loadObj(path, texture, materials, options)
    local mesh, parsed = ObjLoader.load(path, texture)
    return LevelMesh.new(mesh, parsed, materials, options)
end

function LevelMesh.load(basePath, texture, materials, options)
    if love.filesystem.getInfo(basePath .. ".mesh") then
        return LevelMesh.loadMeshBin(basePath .. ".mesh", texture, materials, options), "meshbin"
    end
    return LevelMesh.loadObj(basePath .. ".obj", texture, materials, options), "obj"
end

function LevelMesh.loadFromManifest(path, resourceManager)
    local manifest = loadManifestModule(path)
    local materials = compileMaterials(manifest.materials, resourceResolver(resourceManager))
    local default = materials.default or DEFAULT_MATERIAL
    local texture = default.albedoTexture or default.texture
    local level, source = LevelMesh.load(manifest.mesh, texture, materials, manifest.render)
    level.manifest = manifest
    return level, source
end

function LevelMesh:materialFor(object)
    return self.materials[object.material or "default"] or self.defaultMaterial
end

function LevelMesh.worldSphere(object, model)
    model = model or Mat4.new()
    local center = object.center or { 0, 0, 0 }
    local x, y, z = model:transformPoint(center[1] or 0, center[2] or 0, center[3] or 0)
    return x, y, z, (object.boundingRadius or 0) * maxAxisScale(model)
end

-- 下发一个材质的 uniform。引擎只认识通用 PBR 字段——游戏专属的材质字段
-- （水面、地表状态等）由 materialSender(shader, material) 自行下发，
-- 见 engine/rendering/WaterMaterial.lua 与各游戏包内的同类模块。
function LevelMesh.applyMaterial(shader, mesh, material, materialSender)
    material = material or DEFAULT_MATERIAL
    local albedo = material.albedoTexture or material.texture
    if albedo then mesh:setTexture(albedo) end
    if shader then
        Fuc.safeSend(shader, "u_materialColor", materialColor(material))
        Fuc.safeSend(shader, "u_metallic", material.metallic or DEFAULT_MATERIAL.metallic)
        Fuc.safeSend(shader, "u_roughness", material.roughness or DEFAULT_MATERIAL.roughness)
        Fuc.safeSend(shader, "u_ao", material.ao or DEFAULT_MATERIAL.ao)
        Fuc.safeSend(shader, "u_normalScale", material.normalScale or DEFAULT_MATERIAL.normalScale)
        Fuc.safeSend(shader, "u_hasNormalMap", material.normalTexture and 1 or 0)
        Fuc.safeSend(shader, "u_hasPbrMap", material.pbrTexture and 1 or 0)
        Fuc.safeSend(shader, "u_hasRoughnessMap", material.roughnessTexture and 1 or 0)
        Fuc.safeSend(shader, "u_hasAoMap", material.aoTexture and 1 or 0)
        Fuc.safeSend(shader, "u_hasAlphaMask", material.alphaMaskTexture and 1 or 0)
        Fuc.safeSend(shader, "u_alphaCutoff", material.alphaCutoff or 0.01)
        if material.normalTexture then Fuc.safeSend(shader, "u_normalTex", material.normalTexture) end
        if material.pbrTexture then Fuc.safeSend(shader, "u_pbrTex", material.pbrTexture) end
        if material.roughnessTexture then Fuc.safeSend(shader, "u_roughnessTex", material.roughnessTexture) end
        if material.aoTexture then Fuc.safeSend(shader, "u_aoTex", material.aoTexture) end
        if material.alphaMaskTexture then Fuc.safeSend(shader, "u_alphaMask", material.alphaMaskTexture) end
        if materialSender then materialSender(shader, material) end
        love.graphics.setColor(1, 1, 1, 1)
    else
        local color = materialColor(material)
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    end
end

function LevelMesh:drawObjects(options)
    options = options or {}
    local mesh = self.mesh
    local model = options.model or self._identity
    local shader = options.shader
    local stats = options.stats
    local draw = options.draw
    -- 游戏专属材质字段的下发钩子；shadow pass 这类不需要材质的趟直接不传
    local materialSender = options.materialSender

    if shader then
        shader:send("u_model", "column", model)
        if options.normalMatrix then
            shader:send("u_normalMatrix", "column", options.normalMatrix)
        end
    end

    for _, object in ipairs(self.objects) do
        local x, y, z, radius = LevelMesh.worldSphere(object, model)
        if options.camera and not options.camera:isSphereVisible(x, y, z, radius) then
            if stats then stats.culled = (stats.culled or 0) + 1 end
        else
            local material = self:materialFor(object)
            LevelMesh.applyMaterial(shader, mesh, material, materialSender)
            mesh:setDrawRange(object.indexStart, object.indexCount)
            if draw then draw(mesh, object, material)
            else love.graphics.draw(mesh) end
            if stats then stats.drawn = (stats.drawn or 0) + 1 end
        end
    end

    mesh:setDrawRange()
    love.graphics.setColor(1, 1, 1, 1)
end

function LevelMesh:release()
    if self.mesh then
        self.mesh:release()
        self.mesh = nil
    end
end

return LevelMesh
