-- 单方向光实时阴影图。颜色通道存储 light-space depth，Canvas 自带深度缓冲负责最近面。
local Fuc = require("engine.utils.Fuc")
local Mat4 = require("engine.math.Mat4")
local Vec3 = require("engine.math.Vec3")

local ShadowMap = {}
ShadowMap.__index = ShadowMap

function ShadowMap.new(canvas, shader, options)
    options = options or {}
    local self = setmetatable({}, ShadowMap)
    self.canvas = assert(canvas, "ShadowMap requires a canvas")
    self.shader = assert(shader, "ShadowMap requires a depth shader")
    self.range = options.range or 72
    self.distance = options.distance or 92
    self.near = options.near or 1
    self.far = options.far or 190
    self.strength = options.strength or 0.58
    self.bias = options.bias or 0.0018
    self.fadeStart = options.fadeStart or self.range * 0.72
    self.center = Vec3.new()
    self.eye = Vec3.new()
    self.up = Vec3.new(0, 1, 0)
    self._view = Mat4.new()
    self._projection = Mat4.new()
    self.viewProjection = Mat4.new()
    self._resolution = { self.canvas:getWidth(), self.canvas:getHeight() }
    return self
end

function ShadowMap:update(lightDir, focus)
    -- 阴影图随视点滑动时，若投影没有对齐到 shadow texel，静态物会在采样格子间
    -- 来回跳动（shadow swimming）。将光源平面内的中心吸附到一个 texel 的世界尺寸。
    local lx, ly, lz = lightDir.x, lightDir.y, lightDir.z
    local rx, ry, rz = lz, 0, -lx -- cross(worldUp, lightDir)
    local rightLength = math.sqrt(rx * rx + rz * rz)
    rx, ry, rz = rx / rightLength, 0, rz / rightLength
    local ux = ly * rz - lz * ry
    local uy = lz * rx - lx * rz
    local uz = lx * ry - ly * rx
    local texelWorldSize = (self.range * 2) / self.canvas:getWidth()
    local planeX = focus.x * rx + focus.y * ry + focus.z * rz
    local planeY = focus.x * ux + focus.y * uy + focus.z * uz
    local snappedX = math.floor(planeX / texelWorldSize + 0.5) * texelWorldSize
    local snappedY = math.floor(planeY / texelWorldSize + 0.5) * texelWorldSize
    self.center:set(
        focus.x + (snappedX - planeX) * rx + (snappedY - planeY) * ux,
        focus.y + (snappedX - planeX) * ry + (snappedY - planeY) * uy,
        focus.z + (snappedX - planeX) * rz + (snappedY - planeY) * uz)
    self.eye:set(
        self.center.x + lightDir.x * self.distance,
        self.center.y + lightDir.y * self.distance,
        self.center.z + lightDir.z * self.distance)
    self._view:setLookAt(self.eye, self.center, self.up)
    self._projection:setOrthographic(-self.range, self.range, -self.range, self.range,
        self.near, self.far, true)
    Mat4.mulTo(self.viewProjection, self._projection, self._view)
end

function ShadowMap:send(shader)
    self._resolution[1], self._resolution[2] = self.canvas:getWidth(), self.canvas:getHeight()
    Fuc.safeSend(shader, "u_hasShadowMap", 1)
    Fuc.safeSend(shader, "u_shadowMap", self.canvas)
    Fuc.safeSend(shader, "u_lightViewProj", "column", self.viewProjection)
    Fuc.safeSend(shader, "u_shadowTexelSize", { 1 / self._resolution[1], 1 / self._resolution[2] })
    Fuc.safeSend(shader, "u_shadowStrength", self.strength)
    Fuc.safeSend(shader, "u_shadowBias", self.bias)
    Fuc.safeSend(shader, "u_shadowCenter", { self.center.x, self.center.y, self.center.z })
    Fuc.safeSend(shader, "u_shadowFadeStart", self.fadeStart)
    Fuc.safeSend(shader, "u_shadowRange", self.range)
end

return ShadowMap
