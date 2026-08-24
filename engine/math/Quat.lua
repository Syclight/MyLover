-- 四元数（单位四元数表示三维旋转）。
-- 约定：{ x, y, z, w }，w 为实部；组合顺序 mulTo(out, a, b) 表示"先施加 b 再施加 a"
-- （与矩阵乘法 a*b 一致）。
--
-- 与 Vec3 相同的设计取舍：普通 Lua 表 + out 参数就地写入，热路径零分配。
local Quat = {}
Quat.__index = Quat

local function new(x, y, z, w)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0, w = w or 1 }, Quat)
end

Quat.new = new

function Quat.identity()
    return new(0, 0, 0, 1)
end

function Quat:set(x, y, z, w)
    self.x, self.y, self.z, self.w = x, y, z, w
    return self
end

function Quat:copy(source)
    self.x, self.y, self.z, self.w = source.x, source.y, source.z, source.w
    return self
end

function Quat:clone()
    return new(self.x, self.y, self.z, self.w)
end

-- 绕单位轴 axis 旋转 angle 弧度（axis 必须已归一化）
function Quat:setAxisAngle(axis, angle)
    local half = angle * 0.5
    local s = math.sin(half)
    self.x, self.y, self.z, self.w = axis.x * s, axis.y * s, axis.z * s, math.cos(half)
    return self
end

function Quat.fromAxisAngle(axis, angle)
    return new():setAxisAngle(axis, angle)
end

-- 欧拉角构造（yaw 绕 Y，pitch 绕 X，roll 绕 Z；应用顺序 roll→pitch→yaw）
function Quat:setEuler(yaw, pitch, roll)
    local cy, sy = math.cos(yaw * 0.5), math.sin(yaw * 0.5)
    local cp, sp = math.cos(pitch * 0.5), math.sin(pitch * 0.5)
    local cr, sr = math.cos(roll * 0.5), math.sin(roll * 0.5)
    self.w = cy * cp * cr + sy * sp * sr
    self.x = cy * sp * cr + sy * cp * sr
    self.y = sy * cp * cr - cy * sp * sr
    self.z = cy * cp * sr - sy * sp * cr
    return self
end

-- out = a * b（out 不能与 a/b 同对象）
function Quat.mulTo(out, a, b)
    local ax, ay, az, aw = a.x, a.y, a.z, a.w
    local bx, by, bz, bw = b.x, b.y, b.z, b.w
    out.x = aw * bx + ax * bw + ay * bz - az * by
    out.y = aw * by - ax * bz + ay * bw + az * bx
    out.z = aw * bz + ax * by - ay * bx + az * bw
    out.w = aw * bw - ax * bx - ay * by - az * bz
    return out
end

function Quat:normalize()
    local len = math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w)
    if len < 1e-12 then
        self.x, self.y, self.z, self.w = 0, 0, 0, 1
        return self
    end
    local inv = 1.0 / len
    self.x, self.y, self.z, self.w = self.x * inv, self.y * inv, self.z * inv, self.w * inv
    return self
end

-- 球面插值：out = slerp(a, b, t)。配合 Timestep.alpha 做旋转插值。
-- 夹角极小时退化为线性插值（数值稳定）。
function Quat.slerpTo(out, a, b, t)
    local ax, ay, az, aw = a.x, a.y, a.z, a.w
    local bx, by, bz, bw = b.x, b.y, b.z, b.w

    local cosom = ax * bx + ay * by + az * bz + aw * bw
    -- 取短弧：点积为负时翻转 b
    if cosom < 0 then
        cosom = -cosom
        bx, by, bz, bw = -bx, -by, -bz, -bw
    end

    local scale0, scale1
    if 1 - cosom > 1e-6 then
        local omega = math.acos(cosom)
        local sinom = math.sin(omega)
        scale0 = math.sin((1 - t) * omega) / sinom
        scale1 = math.sin(t * omega) / sinom
    else
        scale0, scale1 = 1 - t, t
    end

    out.x = scale0 * ax + scale1 * bx
    out.y = scale0 * ay + scale1 * by
    out.z = scale0 * az + scale1 * bz
    out.w = scale0 * aw + scale1 * bw
    return out
end

-- 用该旋转变换向量：out = q * v * q⁻¹（out 可与 v 同对象）
function Quat.rotateVec3To(out, q, v)
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    local vx, vy, vz = v.x, v.y, v.z
    -- t = 2 * cross(q.xyz, v)
    local tx = 2 * (qy * vz - qz * vy)
    local ty = 2 * (qz * vx - qx * vz)
    local tz = 2 * (qx * vy - qy * vx)
    -- out = v + q.w * t + cross(q.xyz, t)
    out.x = vx + qw * tx + (qy * tz - qz * ty)
    out.y = vy + qw * ty + (qz * tx - qx * tz)
    out.z = vz + qw * tz + (qx * ty - qy * tx)
    return out
end

function Quat.__tostring(q)
    return string.format("Quat(%.4f, %.4f, %.4f, %.4f)", q.x, q.y, q.z, q.w)
end

return Quat
