-- 三维向量。
--
-- 设计取舍：用普通 Lua 表（{x,y,z} 字段）而非 FFI struct——
--   * 纯 Lua，测试环境无需 love/LuaJIT 也能跑；
--   * LuaJIT 对小表的优化已足够 P0 阶段使用；
--   * 若日后 profiling 证明热点在此，可在保持同一 API 的前提下换 FFI 实现。
--
-- GC 纪律：所有可能出现在每帧热路径的方法都提供 out 参数（就地写入），
-- 运算符重载（+ - *）会分配新表，只建议在初始化/低频代码里使用。
local Vec3 = {}
Vec3.__index = Vec3

local function new(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec3)
end

Vec3.new = new

function Vec3:set(x, y, z)
    self.x, self.y, self.z = x, y, z
    return self
end

function Vec3:copy(source)
    self.x, self.y, self.z = source.x, source.y, source.z
    return self
end

function Vec3:clone()
    return new(self.x, self.y, self.z)
end

-- out = a + b（out 可以与 a 或 b 是同一个对象）
function Vec3.addTo(out, a, b)
    out.x, out.y, out.z = a.x + b.x, a.y + b.y, a.z + b.z
    return out
end

function Vec3.subTo(out, a, b)
    out.x, out.y, out.z = a.x - b.x, a.y - b.y, a.z - b.z
    return out
end

function Vec3.scaleTo(out, a, s)
    out.x, out.y, out.z = a.x * s, a.y * s, a.z * s
    return out
end

function Vec3.dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

-- out = a × b（注意：out 不能与 a 或 b 是同一个对象，否则中途覆写）
function Vec3.crossTo(out, a, b)
    local x = a.y * b.z - a.z * b.y
    local y = a.z * b.x - a.x * b.z
    local z = a.x * b.y - a.y * b.x
    out.x, out.y, out.z = x, y, z
    return out
end

function Vec3:length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

function Vec3:lengthSquared()
    return self.x * self.x + self.y * self.y + self.z * self.z
end

-- 就地归一化；零向量保持不变并返回 false
function Vec3:normalize()
    local len = self:length()
    if len < 1e-12 then return self, false end
    local inv = 1.0 / len
    self.x, self.y, self.z = self.x * inv, self.y * inv, self.z * inv
    return self, true
end

-- out = a + (b - a) * t，配合 Timestep.alpha 做渲染插值
function Vec3.lerpTo(out, a, b, t)
    out.x = a.x + (b.x - a.x) * t
    out.y = a.y + (b.y - a.y) * t
    out.z = a.z + (b.z - a.z) * t
    return out
end

function Vec3.distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 运算符重载：会分配新表，只用于初始化/低频代码
function Vec3.__add(a, b) return new(a.x + b.x, a.y + b.y, a.z + b.z) end
function Vec3.__sub(a, b) return new(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vec3.__mul(a, b)
    if type(a) == "number" then return new(a * b.x, a * b.y, a * b.z) end
    return new(a.x * b, a.y * b, a.z * b)
end
function Vec3.__unm(a) return new(-a.x, -a.y, -a.z) end
function Vec3.__tostring(v)
    return string.format("Vec3(%.4f, %.4f, %.4f)", v.x, v.y, v.z)
end

return Vec3
