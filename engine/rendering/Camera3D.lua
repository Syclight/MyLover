-- 3D 相机：透视投影 + lookAt 视图 + 视锥剔除。
-- 与 2D 的 engine/rendering/Camera.lua 并存，互不依赖。
--
-- 用法（场景 enter）：
--   local cam = Camera3D.new()
--   cam:setPerspective(math.rad(60), nil, 0.1, 100)  -- aspect=nil 则跟随窗口
--   cam:setPosition(0, 2, 5)
--   cam:lookAt(0, 0, 0)
-- 绘制时：
--   shader:send("u_viewProj", "column", cam:getViewProjection())
--   love.graphics.setFrontFaceWinding(cam:frontFaceWinding())
-- 剔除：
--   if cam:isSphereVisible(x, y, z, radius) then ... end
--
-- 注意：矩阵在读取时惰性重建（脏标记），随便调 setPosition/lookAt 不产生开销。
local Mat4 = require("engine.math.Mat4")
local Vec3 = require("engine.math.Vec3")

local Camera3D = {}
Camera3D.__index = Camera3D

function Camera3D.new()
    local self = setmetatable({}, Camera3D)
    self.position = Vec3.new(0, 0, 5)
    self.target = Vec3.new(0, 0, 0)
    self.up = Vec3.new(0, 1, 0)

    self.fovy = math.rad(60)
    self.aspect = nil     -- nil = 每次读取时跟随窗口尺寸
    self.near = 0.1
    self.far = 100.0
    -- 渲染到 Canvas 时需要翻转 NDC 的 y（LÖVE 对 Canvas 的内部 y 翻转被自定义
    -- 投影绕过了）。若改为直接画到 backbuffer，请设为 false。
    self.flipY = true

    self._view = Mat4.new()
    self._proj = Mat4.new()
    self._viewProj = Mat4.new()
    self._frustum = {}                 -- 6 个平面 {x,y,z,w}，法线指向视锥内部
    for i = 1, 6 do self._frustum[i] = { x = 0, y = 0, z = 0, w = 0 } end
    self._dirty = true
    self._lastAspect = nil
    self._viewportWidth = nil
    self._viewportHeight = nil
    return self
end

function Camera3D:setPerspective(fovy, aspect, near, far)
    self.fovy = fovy or self.fovy
    self.aspect = aspect
    self.near = near or self.near
    self.far = far or self.far
    self._dirty = true
    return self
end

function Camera3D:setPosition(x, y, z)
    self.position:set(x, y, z)
    self._dirty = true
    return self
end

function Camera3D:lookAt(x, y, z)
    self.target:set(x, y, z)
    self._dirty = true
    return self
end

function Camera3D:setUp(x, y, z)
    self.up:set(x, y, z)
    self._dirty = true
    return self
end

-- 窗口/画布尺寸变化时调用（或依赖 aspect=nil 的自动跟随）。
-- width/height 传 nil 时回到 love.graphics.getDimensions()。
function Camera3D:resize(width, height)
    self._viewportWidth = width
    self._viewportHeight = height
    self._dirty = true
end

Camera3D.setViewport = Camera3D.resize

-- 正面环绕方向（配合 love.graphics.setFrontFaceWinding 使用）。
-- 两次翻转会相互抵消：投影 flipY 让 CCW 建模的三角形在 NDC 里变成 CW，
-- 但 LÖVE 在 Canvas 激活时内部还会再翻一次绕向（Graphics.cpp setFrontFaceWinding:
-- "Flip front face winding when rendering to a canvas, since our projection
-- matrix is flipped."）。因此需要的声明取决于 flipY XOR Canvas 是否激活——
-- 必须在 setCanvas 之后、绘制之前调用，才能读到正确的渲染目标。
function Camera3D:frontFaceWinding()
    local flipped = self.flipY
    if love.graphics.getCanvas() then flipped = not flipped end
    return flipped and "cw" or "ccw"
end

local function currentAspect(self)
    if self.aspect then return self.aspect end
    local w, h = self._viewportWidth, self._viewportHeight
    if not (w and h and h > 0) then
        w, h = love.graphics.getDimensions()
    end
    return w / h
end

local function rebuild(self)
    local aspect = currentAspect(self)
    if not self._dirty and aspect == self._lastAspect then return end
    self._lastAspect = aspect

    self._proj:setPerspective(self.fovy, aspect, self.near, self.far, self.flipY)
    self._view:setLookAt(self.position, self.target, self.up)
    Mat4.mulTo(self._viewProj, self._proj, self._view)

    -- Gribb-Hartmann 平面提取：viewProj 的行组合出 6 个视锥平面。
    -- 列主序平铺下，行 r = { m[r], m[4+r], m[8+r], m[12+r] }。
    local m = self._viewProj
    local r1x, r1y, r1z, r1w = m[1], m[5], m[9], m[13]
    local r2x, r2y, r2z, r2w = m[2], m[6], m[10], m[14]
    local r3x, r3y, r3z, r3w = m[3], m[7], m[11], m[15]
    local r4x, r4y, r4z, r4w = m[4], m[8], m[12], m[16]

    local planes = self._frustum
    local function setPlane(p, x, y, z, w)
        local len = math.sqrt(x * x + y * y + z * z)
        if len > 1e-12 then
            p.x, p.y, p.z, p.w = x / len, y / len, z / len, w / len
        else
            p.x, p.y, p.z, p.w = 0, 0, 0, 1 -- 退化平面：永远可见
        end
    end
    setPlane(planes[1], r4x + r1x, r4y + r1y, r4z + r1z, r4w + r1w) -- 左
    setPlane(planes[2], r4x - r1x, r4y - r1y, r4z - r1z, r4w - r1w) -- 右
    setPlane(planes[3], r4x + r2x, r4y + r2y, r4z + r2z, r4w + r2w) -- 下（flipY 时为上）
    setPlane(planes[4], r4x - r2x, r4y - r2y, r4z - r2z, r4w - r2w) -- 上（flipY 时为下）
    setPlane(planes[5], r4x + r3x, r4y + r3y, r4z + r3z, r4w + r3w) -- 近
    setPlane(planes[6], r4x - r3x, r4y - r3y, r4z - r3z, r4w - r3w) -- 远

    self._dirty = false
end

function Camera3D:getView()
    rebuild(self)
    return self._view
end

function Camera3D:getProjection()
    rebuild(self)
    return self._proj
end

function Camera3D:getViewProjection()
    rebuild(self)
    return self._viewProj
end

-- 球体视锥剔除。返回 true = 可能可见（保守判定，不产生误剔除）。
function Camera3D:isSphereVisible(x, y, z, radius)
    rebuild(self)
    for i = 1, 6 do
        local p = self._frustum[i]
        if p.x * x + p.y * y + p.z * z + p.w < -radius then
            return false
        end
    end
    return true
end

function Camera3D:isPointVisible(x, y, z)
    return self:isSphereVisible(x, y, z, 0)
end

return Camera3D
