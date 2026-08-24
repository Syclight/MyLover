local json = require("engine.utils.json")

local ResourceManager = {}

ResourceManager.global = {}
ResourceManager.scene = {}
ResourceManager._nextScopeId = 0
ResourceManager._canvasSpecs = setmetatable({}, { __mode = "k" })

local function shallowCopy(source)
    if not source then return nil end
    local copy = {}
    for key, value in pairs(source) do copy[key] = value end
    return copy
end

local function compactSettings(settings)
    if not settings then return nil end
    for _ in pairs(settings) do return settings end
    return nil
end

local function canvasFormats()
    local getter = love.graphics.getCanvasFormats or love.graphics.getImageFormats
    if not getter then return nil end
    local ok, formats = pcall(getter)
    return ok and formats or nil
end

local function fallbackCanvasSettings(settings)
    if not (settings and settings.format) then return nil end
    local fallback = shallowCopy(settings)
    local formats = canvasFormats()
    if formats then
        fallback.format = (formats[settings.format] and settings.format)
            or (formats.r16f and "r16f")
            or (formats.rgba16f and "rgba16f")
            or (formats.normal and "normal")
            or (formats.rgba8 and "rgba8")
            or nil
    else
        fallback.format = nil
    end
    return compactSettings(fallback)
end

local function newCanvasWithFallback(width, height, settings)
    local requestedSettings = settings and shallowCopy(settings) or nil
    local ok, canvasOrError = pcall(love.graphics.newCanvas, width, height, requestedSettings)
    if ok then return canvasOrError, requestedSettings end

    local fallback = fallbackCanvasSettings(requestedSettings)
    if fallback == nil and not (requestedSettings and requestedSettings.format) then
        error("ResourceManager error: cannot create canvas: " .. tostring(canvasOrError), 2)
    end

    ok, canvasOrError = pcall(love.graphics.newCanvas, width, height, fallback)
    if ok then return canvasOrError, fallback end
    error("ResourceManager error: cannot create canvas: " .. tostring(canvasOrError), 2)
end

local function releaseStore(store)
    for k, v in pairs(store or {}) do
        if type(v) == "userdata" and v.release then v:release() end
        store[k] = nil
    end
end

local MANIFEST_FIELDS = {
    images = true, sounds = true, music = true, fonts = true,
    json = true, binary = true, shaders = true, canvases = true,
}

local function manifestError(manifestPath, message)
    error("ResourceManager manifest error in " .. tostring(manifestPath) .. ": " .. message, 3)
end

local function requireManifestList(manifest, manifestPath, category)
    local list = manifest[category]
    if list ~= nil and type(list) ~= "table" then
        manifestError(manifestPath, "'" .. category .. "' must be a list")
    end
    return list
end

local function resourceKey(category, entry)
    if category == "fonts" then
        return entry.name or ((entry.path or "font_default") .. "#" .. tostring(entry.size))
    elseif category == "shaders" then
        return entry.name or entry.module or entry.path
    elseif category == "canvases" then
        return entry.name
    end
    return entry.name or entry.path
end

local function validateManifestEntry(manifestPath, category, index, entry)
    if type(entry) ~= "table" then
        manifestError(manifestPath, "'" .. category .. "' entry #" .. index .. " must be a table")
    end
    if category == "fonts" then
        if type(entry.size) ~= "number" then
            manifestError(manifestPath, "fonts entry #" .. index .. " requires numeric size")
        end
    elseif category == "shaders" then
        if not entry.path and not entry.module then
            manifestError(manifestPath, "shaders entry #" .. index .. " requires path or module")
        end
    elseif category == "canvases" then
        if type(entry.name) ~= "string" or entry.name == "" then
            manifestError(manifestPath, "canvases entry #" .. index .. " requires name")
        end
    elseif not entry.path then
        manifestError(manifestPath, category .. " entry #" .. index .. " requires path")
    end
    local key = resourceKey(category, entry)
    if key == nil or key == "" then
        manifestError(manifestPath, category .. " entry #" .. index .. " resolves to an empty resource key")
    end
    return key
end

local function validateManifest(manifest, manifestPath)
    if type(manifest) ~= "table" then
        manifestError(manifestPath, "module must return a table")
    end
    for field in pairs(manifest) do
        if not MANIFEST_FIELDS[field] then
            manifestError(manifestPath, "unknown field '" .. tostring(field) .. "'")
        end
    end
    local seen = {}
    for category in pairs(MANIFEST_FIELDS) do
        local list = requireManifestList(manifest, manifestPath, category)
        for index, entry in ipairs(list or {}) do
            local key = validateManifestEntry(manifestPath, category, index, entry)
            if seen[key] then
                manifestError(manifestPath, "duplicate resource key '" .. tostring(key)
                    .. "' in " .. seen[key] .. " and " .. category .. " entry #" .. index)
            end
            seen[key] = category .. " entry #" .. index
        end
    end
end

local function loadManifestModule(manifestPath)
    local manifest = require(manifestPath:gsub("%.lua$", ""))
    validateManifest(manifest, manifestPath)
    return manifest
end

local function classifyResource(resource)
    if type(resource) == "userdata" then
        if resource.typeOf then
            if resource:typeOf("Canvas") then return "canvases" end
            if resource:typeOf("Image") then return "images" end
            if resource:typeOf("ImageData") then return "imageData" end
            if resource:typeOf("Shader") then return "shaders" end
            if resource:typeOf("Font") then return "fonts" end
            if resource:typeOf("Source") then return "audio" end
        end
        return "userdata"
    end
    if type(resource) == "string" then return "binary" end
    if type(resource) == "table" then return "tables" end
    return type(resource)
end

local function countStore(store)
    local stats = { total = 0 }
    for _, resource in pairs(store or {}) do
        local kind = classifyResource(resource)
        stats.total = stats.total + 1
        stats[kind] = (stats[kind] or 0) + 1
    end
    return stats
end

local function mergeStats(left, right)
    local total = {}
    for key, value in pairs(left or {}) do total[key] = (total[key] or 0) + value end
    for key, value in pairs(right or {}) do total[key] = (total[key] or 0) + value end
    return total
end

function ResourceManager:createSceneScope(label)
    self._nextScopeId = self._nextScopeId + 1
    return {
        id = self._nextScopeId,
        label = label or ("scene-" .. self._nextScopeId),
        resources = {},
    }
end

function ResourceManager:activateSceneScope(scope)
    self.scene = scope and scope.resources or {}
end

function ResourceManager:releaseSceneScope(scope)
    if not scope then return end
    releaseStore(scope.resources)
    if self.scene == scope.resources then self.scene = {} end
    collectgarbage("step")
end

-------------------------------------------------
--- 重置Canvas分辨率
--- 如果你在游戏中途需要改变画布的分辨率，可以调用这个方法
--- 注意：这会销毁原来的画布并创建一个新的，所以请确保你已经做好了资源管理（比如在场景切换时调用，或者在游戏开始时设置好分辨率）
--- 参数：
---  name: 画布在资源管理器中的键值（必须提供）
---  width: 新的宽度（可选，默认为当前屏幕宽度）
---  height: 新的高度（可选，默认为当前屏幕高度）
---  settings: 画布设置（可选，默认为空表）
---  scope: 资源作用域（可选，默认为 "scene"）
--- -------------------------------------------------
function ResourceManager:resetCanvas(name, width, height, settings, scope)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene

    if not name then
        error("ResourceManager:resetCanvas 必须提供 'name' 作为键值！")
    end

    if not store[name] then
        error("ResourceManager:resetCanvas 无法找到名为 '" .. name .. "' 的画布！")
    end

    -- 销毁原来的画布（如果支持）
    local oldCanvas = store[name]
    local oldSpec = self._canvasSpecs[oldCanvas]
    if type(oldCanvas) == "userdata" and oldCanvas.release then
        oldCanvas:release()
    end

    -- 创建新的画布
    local w = width or love.graphics.getWidth()
    local h = height or love.graphics.getHeight()
    local resolvedSettings = settings or (oldSpec and oldSpec.settings)
    local newCanvas, actualSettings = newCanvasWithFallback(w, h, resolvedSettings)
    store[name] = newCanvas
    self._canvasSpecs[newCanvas] = {
        width = width,
        height = height,
        settings = actualSettings,
        screenSized = width == nil and height == nil,
    }
    return newCanvas
end

-------------------------------------------------
--- 重置所有Canvas分辨率
-------------------------------------------------
function ResourceManager:resetAllCanvases(width, height, settings, scope)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene

    for key, resource in pairs(store) do
        if type(resource) == "userdata" and resource:typeOf("Canvas") then
            local spec = self._canvasSpecs[resource]
            if spec == nil or spec.screenSized then
                self:resetCanvas(key, width, height, settings, scope)
            end
        end
    end
end

-------------------------------------------------
-- 图片
-------------------------------------------------
--- settings（可选，3D 贴图必备）：
---   mipmaps      = true                       远处贴图不闪烁的前提
---   linear       = true                       按线性空间解码（法线/数据贴图必须，颜色贴图别开）
---   wrap         = "repeat" 或 { "repeat", "clamp" }   平铺纹理用 repeat
---   filter       = "linear" 或 { "linear", "nearest" } 采样过滤 (min, mag)
---   anisotropy   = 4                          各向异性过滤（斜视角贴图清晰度）
---   mipmapFilter = "linear" | "nearest" | false        mipmap 间过滤，默认随 mipmaps 开启为 "linear"
function ResourceManager:loadImage(path, scope, name, needData, settings)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then
        return store[key]
    end

    local newImageSettings = nil
    if settings and (settings.mipmaps ~= nil or settings.linear ~= nil) then
        newImageSettings = { mipmaps = settings.mipmaps, linear = settings.linear }
    end
    local image = love.graphics.newImage(path, newImageSettings)
    if settings then
        if settings.wrap then
            if type(settings.wrap) == "table" then
                image:setWrap(settings.wrap[1], settings.wrap[2] or settings.wrap[1])
            else
                image:setWrap(settings.wrap, settings.wrap)
            end
        end
        if settings.filter or settings.anisotropy then
            local f = settings.filter
            local min, mag
            if type(f) == "table" then
                min, mag = f[1], f[2] or f[1]
            else
                min, mag = f or "linear", f or "linear"
            end
            image:setFilter(min, mag, settings.anisotropy)
        end
        if settings.mipmaps and settings.mipmapFilter ~= false and image.setMipmapFilter then
            image:setMipmapFilter(settings.mipmapFilter or "linear")
        end
    end
    store[key] = image
    if needData then
        local imageData = love.image.newImageData(path)
        store[key .. "_data"] = imageData
    end
    return image
end

-------------------------------------------------
-- 音效（短音）
-------------------------------------------------
function ResourceManager:loadSound(path, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then
        return store[key]
    end

    local sound = love.audio.newSource(path, "static")
    store[key] = sound
    return sound
end

-------------------------------------------------
-- 音乐（长音）
-------------------------------------------------
function ResourceManager:loadMusic(path, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then
        return store[key]
    end

    local music = love.audio.newSource(path, "stream")
    store[key] = music
    return music
end

-------------------------------------------------
-- 字体
-------------------------------------------------
function ResourceManager:loadFont(path, size, scope, name)
    -- 默认 scope 与其他 loader 一致（scene）。字体如需跨场景常驻请显式传 "global"。
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    if path == nil then
        -- 加载默认字体（同样要先查缓存，否则每次调用都会新建 Font 并泄漏旧对象）
        local key = name or ("font_default#" .. size)
        if store[key] then
            return store[key]
        end
        local defaultFont = love.graphics.newFont(size)
        store[key] = defaultFont
        return defaultFont
    end

    local key = name or (path .. "#" .. size)

    if store[key] then
        return store[key]
    end

    local font = love.graphics.newFont(path, size)
    store[key] = font
    return font
end

-------------------------------------------------
-- JSON
-------------------------------------------------
--- 【重要】返回的是缓存中的共享 table，请当作只读数据使用！
--- 任何调用方直接修改返回值都会污染缓存，之后所有 get() 拿到的都是脏数据。
--- 如需可变副本，请自行深拷贝。
function ResourceManager:loadJSON(path, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then
        return store[key]
    end

    local content = love.filesystem.read(path)
    local data = json.decode(content) -- 需要 json.lua
    store[key] = data
    return data
end

-------------------------------------------------
-- 二进制
-------------------------------------------------
function ResourceManager:loadBinary(path, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then
        return store[key]
    end

    local content = love.filesystem.read(path)
    store[key] = content
    return content
end

-------------------------------------------------
-- 着色器 (Shader)
-------------------------------------------------
-- 两条加载路径统一过 ShaderPreprocessor：源码内可用 #include "路径" 引公共库
-- （engine/assets/shaders/include/）。无 #include 的源码为零成本透传。
function ResourceManager:loadShader(path, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or path

    if store[key] then return store[key] end

    local ShaderPreprocessor = require("engine.rendering.ShaderPreprocessor")
    local shader = love.graphics.newShader(ShaderPreprocessor.processFile(path))
    store[key] = shader
    return shader
end

-- shader 的 .lua 模块模式（正式约定）：模块返回 GLSL 源码串，
-- 相对 #include 以模块所在目录为基准，其次工程根。
function ResourceManager:loadShaderModule(moduleName, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name or moduleName
    if store[key] then return store[key] end
    local ShaderPreprocessor = require("engine.rendering.ShaderPreprocessor")
    local source = require(moduleName)
    assert(type(source) == "string",
        "shader module '" .. moduleName .. "' must return GLSL source text")
    local shader = love.graphics.newShader(
        ShaderPreprocessor.process(source, ShaderPreprocessor.moduleDir(moduleName), moduleName))
    store[key] = shader
    return shader
end

function ResourceManager:register(name, resource, scope)
    assert(name ~= nil, "ResourceManager:register requires a name")
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    if store[name] and store[name] ~= resource then
        error("ResourceManager:register duplicate resource '" .. tostring(name) .. "'")
    end
    store[name] = resource
    return resource
end

-------------------------------------------------
-- 画布 (Canvas)
-------------------------------------------------
function ResourceManager:createCanvas(width, height, settings, scope, name)
    scope = scope or "scene"
    local store = (scope == "global") and self.global or self.scene
    local key = name 

    if not key then error("必须提供 'name' 作为 Canvas 的键值！") end
    if store[key] then return store[key] end

    -- 如果不传宽高，默认使用当前屏幕分辨率
    local w = width or love.graphics.getWidth()
    local h = height or love.graphics.getHeight()
    local canvas, actualSettings = newCanvasWithFallback(w, h, settings)
    store[key] = canvas
    self._canvasSpecs[canvas] = {
        width = width,
        height = height,
        settings = actualSettings,
        screenSized = width == nil and height == nil,
    }
    return canvas
end

-------------------------------------------------
-- Manifest 自动加载
-------------------------------------------------
function ResourceManager:loadManifest(manifestPath, scope)
    scope = scope or "scene"

    local manifest = loadManifestModule(manifestPath)

    if manifest.images then
        for _, image in ipairs(manifest.images) do
            self:loadImage(image.path, scope, image.name or nil, image.needData or nil, image.settings)
        end
    end

    if manifest.sounds then
        for _, sounds in ipairs(manifest.sounds) do
            self:loadSound(sounds.path, scope, sounds.name or nil)
        end
    end

    if manifest.music then
        for _, music in ipairs(manifest.music) do
            self:loadMusic(music.path, scope, music.name or nil)
        end
    end

    if manifest.fonts then
        for _, font in ipairs(manifest.fonts) do
            self:loadFont(font.path, font.size, scope, font.name or nil)
        end
    end

    if manifest.json then
        for _, json in ipairs(manifest.json) do
            self:loadJSON(json.path, scope, json.name or nil)
        end
    end

    if manifest.binary then
        for _, binary in ipairs(manifest.binary) do
            self:loadBinary(binary.path, scope, binary.name or nil)
        end
    end


    if manifest.shaders then
        for _, shader in ipairs(manifest.shaders) do
            if shader.module then
                self:loadShaderModule(shader.module, scope, shader.name)
            else
                self:loadShader(shader.path, scope, shader.name)
            end
        end
    end

    if manifest.canvases then
        for _, canvas in ipairs(manifest.canvases) do
            self:createCanvas(canvas.width, canvas.height, canvas.settings, scope, canvas.name)
        end
    end
end

-------------------------------------------------
-- Manifest 异步加载资源任务
--- 用于asyncloader.lua，异步资源加载器
-------------------------------------------------
function ResourceManager:createTasksFromManifest(manifestPath, scope)
    local tasks = {}
    local manifest = loadManifestModule(manifestPath)

    if manifest.images then
        for _, image in ipairs(manifest.images) do
            table.insert(tasks, function()
                self:loadImage(image.path, scope, image.name, image.needData, image.settings)
            end)
        end
    end

    if manifest.music then
        for _, music in ipairs(manifest.music) do
            table.insert(tasks, function()
                self:loadMusic(music.path, scope, music.name)
            end)
        end
    end

    if manifest.fonts then
        for _, font in ipairs(manifest.fonts) do
            table.insert(tasks, function()
                self:loadFont(font.path, font.size, scope, font.name)
            end)
        end
    end

    if manifest.sounds then
        for _, sound in ipairs(manifest.sounds) do
            table.insert(tasks, function()
                self:loadSound(sound.path, scope, sound.name)
            end)
        end
    end

    if manifest.json then
        for _, json in ipairs(manifest.json) do
            table.insert(tasks, function()
                self:loadJSON(json.path, scope, json.name)
            end)
        end
    end

    if manifest.binary then
        for _, binary in ipairs(manifest.binary) do
            table.insert(tasks, function()
                self:loadBinary(binary.path, scope, binary.name)
            end)
        end
    end

    if manifest.shaders then
        for _, shader in ipairs(manifest.shaders) do
            table.insert(tasks, function()
                if shader.module then
                    self:loadShaderModule(shader.module, scope, shader.name)
                else
                    self:loadShader(shader.path, scope, shader.name)
                end
            end)
        end
    end

    if manifest.canvases then
        for _, canvas in ipairs(manifest.canvases) do
            table.insert(tasks, function()
                self:createCanvas(canvas.width, canvas.height, canvas.settings, scope, canvas.name)
            end)
        end
    end

    return tasks
end

-------------------------------------------------
-- 获取资源（不创建，只返回）
-------------------------------------------------
function ResourceManager:get(path, scope)
    local res = nil
    if scope == nil then
        res = self.scene[path]
        if res == nil then
            res = self.global[path]
        end
    elseif scope == "scene" then
        res = self.scene[path]
    elseif scope == "global" then
        res = self.global[path]
    end
    return res
end

function ResourceManager:getScopeGlobal(path)
     return self.global[path]
end

function ResourceManager:getScopeScene(path)
     return self.scene[path]
end

function ResourceManager:debugStats()
    local global = countStore(self.global)
    local scene = countStore(self.scene)
    return {
        global = global,
        scene = scene,
        total = mergeStats(global, scene),
    }
end


-------------------------------------------------
-- 卸载
-------------------------------------------------
function ResourceManager:unloadScene()
    releaseStore(self.scene)
    collectgarbage()
end

function ResourceManager:unloadAll()
    self:unloadScene()

    releaseStore(self.global)
    collectgarbage()
end

return ResourceManager
