local Fuc = require("engine.utils.Fuc")
local Vec3 = require("engine.math.Vec3")

local Environment = {}
Environment.__index = Environment

local function cloneColor(value, fallback)
    value = value or fallback
    return { value[1], value[2], value[3], value[4] or 1 }
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function mixColor(a, b, t)
    return {
        lerp(a[1], b[1], t),
        lerp(a[2], b[2], t),
        lerp(a[3], b[3], t),
        lerp(a[4] or 1, b[4] or 1, t),
    }
end

function Environment.new(options)
    options = options or {}
    local lightDir = options.lightDir or Vec3.new(0.42, 0.92, 0.48)
    lightDir:normalize()

    local self = setmetatable({}, Environment)
    self.lightDir = lightDir
    self.ambient = cloneColor(options.ambient, { 0.28, 0.30, 0.32, 1 })
    self.skyIrradiance = cloneColor(options.skyIrradiance, { 0.18, 0.22, 0.28, 1 })
    self.horizonIrradiance = cloneColor(options.horizonIrradiance, { 0.20, 0.20, 0.18, 1 })
    self.groundIrradiance = cloneColor(options.groundIrradiance, { 0.10, 0.09, 0.07, 1 })
    self.exposure = options.exposure or 1.0
    self.sunIntensity = options.sunIntensity or 2.5
    self.fogStart = options.fogStart or 0
    self.fogDensity = options.fogDensity or 0.004
    self.fogHeightFalloff = options.fogHeightFalloff or 0.025

    self.skyTop = cloneColor(options.skyTop, { 0.34, 0.56, 0.88, 1 })
    self.skyMid = cloneColor(options.skyMid, { 0.58, 0.75, 0.94, 1 })
    self.horizon = cloneColor(options.horizon, { 0.86, 0.91, 0.96, 1 })
    self.groundHaze = cloneColor(options.groundHaze, { 0.55, 0.62, 0.52, 1 })
    self.sunColor = cloneColor(options.sunColor, { 1.0, 0.86, 0.52, 1 })
    self.skyShader = options.skyShader
    self.skyTexture = options.skyTexture
    self.skyRotation = options.skyRotation or 0
    self.cloudCoverage = options.cloudCoverage or 0.55
    self.cloudScale = options.cloudScale or 1.35
    self.cloudSpeed = options.cloudSpeed or 0.004
    return self
end

function Environment:send(shader)
    Fuc.safeSend(shader, "u_lightDir", { self.lightDir.x, self.lightDir.y, self.lightDir.z })
    Fuc.safeSend(shader, "u_ambient", { self.ambient[1], self.ambient[2], self.ambient[3] })
    Fuc.safeSend(shader, "u_skyIrradiance", { self.skyIrradiance[1], self.skyIrradiance[2], self.skyIrradiance[3] })
    Fuc.safeSend(shader, "u_horizonIrradiance", {
        self.horizonIrradiance[1],
        self.horizonIrradiance[2],
        self.horizonIrradiance[3],
    })
    Fuc.safeSend(shader, "u_groundIrradiance", {
        self.groundIrradiance[1],
        self.groundIrradiance[2],
        self.groundIrradiance[3],
    })
    Fuc.safeSend(shader, "u_sunColor", { self.sunColor[1], self.sunColor[2], self.sunColor[3] })
    Fuc.safeSend(shader, "u_sunIntensity", self.sunIntensity)
    -- 天空"辐亮度"（skybox 的显示色），供水面等镜面反射直接取色；
    -- 与上面的 skyIrradiance（余弦加权辐照度）语义不同，别混用。
    Fuc.safeSend(shader, "u_skyColorTop", { self.skyTop[1], self.skyTop[2], self.skyTop[3] })
    Fuc.safeSend(shader, "u_skyColorHorizon", { self.horizon[1], self.horizon[2], self.horizon[3] })
    Fuc.safeSend(shader, "u_fogColor", { self.horizon[1], self.horizon[2], self.horizon[3] })
    Fuc.safeSend(shader, "u_fogStart", self.fogStart)
    Fuc.safeSend(shader, "u_fogDensity", self.fogDensity)
    Fuc.safeSend(shader, "u_fogHeightFalloff", self.fogHeightFalloff)
    Fuc.safeSend(shader, "u_exposure", self.exposure)
end

local function cameraBasis(camera)
    local fx = camera.target.x - camera.position.x
    local fy = camera.target.y - camera.position.y
    local fz = camera.target.z - camera.position.z
    local forwardLength = math.sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / forwardLength, fy / forwardLength, fz / forwardLength

    local rx = fy * camera.up.z - fz * camera.up.y
    local ry = fz * camera.up.x - fx * camera.up.z
    local rz = fx * camera.up.y - fy * camera.up.x
    local rightLength = math.sqrt(rx * rx + ry * ry + rz * rz)
    rx, ry, rz = rx / rightLength, ry / rightLength, rz / rightLength

    local ux = ry * fz - rz * fy
    local uy = rz * fx - rx * fz
    local uz = rx * fy - ry * fx
    return { fx, fy, fz }, { rx, ry, rz }, { ux, uy, uz }
end

function Environment:drawSkybox(width, height, camera, time)
    local w = width or love.graphics.getWidth()
    local h = height or love.graphics.getHeight()
    if self.skyShader and camera then
        local forward, right, up = cameraBasis(camera)
        Fuc.safeSend(self.skyShader, "u_resolution", { w, h })
        Fuc.safeSend(self.skyShader, "u_viewForward", forward)
        Fuc.safeSend(self.skyShader, "u_viewRight", right)
        Fuc.safeSend(self.skyShader, "u_viewUp", up)
        Fuc.safeSend(self.skyShader, "u_sunDir", { self.lightDir.x, self.lightDir.y, self.lightDir.z })
        Fuc.safeSend(self.skyShader, "u_sunColor", { self.sunColor[1], self.sunColor[2], self.sunColor[3] })
        Fuc.safeSend(self.skyShader, "u_skyTop", { self.skyTop[1], self.skyTop[2], self.skyTop[3] })
        Fuc.safeSend(self.skyShader, "u_skyHorizon", { self.horizon[1], self.horizon[2], self.horizon[3] })
        Fuc.safeSend(self.skyShader, "u_groundHaze", { self.groundHaze[1], self.groundHaze[2], self.groundHaze[3] })
        Fuc.safeSend(self.skyShader, "u_tanHalfFov", math.tan(camera.fovy * 0.5))
        Fuc.safeSend(self.skyShader, "u_aspect", w / h)
        Fuc.safeSend(self.skyShader, "u_time", time or 0)
        Fuc.safeSend(self.skyShader, "u_exposure", self.exposure)
        Fuc.safeSend(self.skyShader, "u_cloudCoverage", self.cloudCoverage)
        Fuc.safeSend(self.skyShader, "u_cloudScale", self.cloudScale)
        Fuc.safeSend(self.skyShader, "u_cloudSpeed", self.cloudSpeed)
        Fuc.safeSend(self.skyShader, "u_hasSkyTexture", self.skyTexture and 1 or 0)
        Fuc.safeSend(self.skyShader, "u_skyRotation", self.skyRotation)
        if self.skyTexture then Fuc.safeSend(self.skyShader, "u_skyTexture", self.skyTexture) end

        love.graphics.setShader(self.skyShader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setShader()
        return
    end

    local strips = 40

    love.graphics.setShader()
    love.graphics.setBlendMode("alpha", "alphamultiply")
    for i = 0, strips - 1 do
        local t = i / strips
        local color
        if t < 0.45 then
            color = mixColor(self.skyTop, self.skyMid, t / 0.45)
        elseif t < 0.72 then
            color = mixColor(self.skyMid, self.horizon, (t - 0.45) / 0.27)
        else
            color = mixColor(self.horizon, self.groundHaze, (t - 0.72) / 0.28)
        end
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        love.graphics.rectangle("fill", 0, t * h, w, h / strips + 1)
    end

    love.graphics.setColor(self.groundHaze[1], self.groundHaze[2], self.groundHaze[3], 0.22)
    love.graphics.rectangle("fill", 0, h * 0.72, w, h * 0.18)
    love.graphics.setColor(1, 1, 1, 1)
end

return Environment
