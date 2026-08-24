-- 4x4 矩阵，列主序（column-major）平铺存储：m[1..4] 是第一列。
-- 元素 (行 r, 列 c) = m[(c-1)*4 + r]，与 OpenGL/GLSL 内存布局一致，
-- 因此实例可直接传给 LÖVE：shader:send(name, "column", mat)。
--
-- 约定：右手坐标系，相机看向 -Z；乘法 mulTo(out, a, b) 即数学上的 a*b
-- （先施加 b 再施加 a）。所有热路径方法用 out 参数就地写入，零分配。
local Mat4 = {}
Mat4.__index = Mat4

local function new()
    return setmetatable({
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }, Mat4)
end

Mat4.new = new

function Mat4:identity()
    self[1], self[2], self[3], self[4] = 1, 0, 0, 0
    self[5], self[6], self[7], self[8] = 0, 1, 0, 0
    self[9], self[10], self[11], self[12] = 0, 0, 1, 0
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1
    return self
end

function Mat4:copy(source)
    for i = 1, 16 do self[i] = source[i] end
    return self
end

function Mat4:clone()
    return new():copy(self)
end

-- out = a * b（out 不能与 a/b 同对象）
function Mat4.mulTo(out, a, b)
    for c = 0, 3 do
        local b1, b2, b3, b4 = b[c * 4 + 1], b[c * 4 + 2], b[c * 4 + 3], b[c * 4 + 4]
        out[c * 4 + 1] = a[1] * b1 + a[5] * b2 + a[9] * b3 + a[13] * b4
        out[c * 4 + 2] = a[2] * b1 + a[6] * b2 + a[10] * b3 + a[14] * b4
        out[c * 4 + 3] = a[3] * b1 + a[7] * b2 + a[11] * b3 + a[15] * b4
        out[c * 4 + 4] = a[4] * b1 + a[8] * b2 + a[12] * b3 + a[16] * b4
    end
    return out
end

-- 变换一个点（w=1），返回 x, y, z, w（不做透视除法，调用方按需除 w）
function Mat4:transformPoint(x, y, z)
    local m = self
    local ox = m[1] * x + m[5] * y + m[9] * z + m[13]
    local oy = m[2] * x + m[6] * y + m[10] * z + m[14]
    local oz = m[3] * x + m[7] * y + m[11] * z + m[15]
    local ow = m[4] * x + m[8] * y + m[12] * z + m[16]
    return ox, oy, oz, ow
end

-- 透视投影（OpenGL 风格，NDC z 范围 [-1,1]）。
-- flipY = true 时把 NDC 的 y 翻转：LÖVE 在向 Canvas 渲染 2D 内容时内部会做
-- y 翻转，我们自定义投影绕过了它，所以【渲染到 Canvas 时应传 flipY=true】，
-- 否则画面上下颠倒。注意翻转 y 会反转三角形环绕方向——配套的正面环绕
-- 设置见 Camera3D:frontFaceWinding()。
function Mat4:setPerspective(fovy, aspect, near, far, flipY)
    local f = 1.0 / math.tan(fovy * 0.5)
    local ySign = flipY and -1.0 or 1.0
    self:identity()
    self[1] = f / aspect
    self[6] = f * ySign
    self[11] = (far + near) / (near - far)
    self[12] = -1
    self[15] = (2 * far * near) / (near - far)
    self[16] = 0
    return self
end

-- 正交投影：用于方向光阴影等不需要透视收缩的渲染 pass。
function Mat4:setOrthographic(left, right, bottom, top, near, far, flipY)
    local width = right - left
    local height = top - bottom
    local depth = far - near
    assert(math.abs(width) > 1e-12 and math.abs(height) > 1e-12 and math.abs(depth) > 1e-12,
        "Mat4:setOrthographic requires non-zero extents")
    local ySign = flipY and -1.0 or 1.0
    self:identity()
    self[1] = 2.0 / width
    self[6] = ySign * 2.0 / height
    self[11] = -2.0 / depth
    self[13] = -(right + left) / width
    self[14] = ySign * -(top + bottom) / height
    self[15] = -(far + near) / depth
    return self
end

-- 视图矩阵：相机位于 eye，看向 target，up 为世界上方向（三者都是 Vec3 风格 {x,y,z}）
function Mat4:setLookAt(eye, target, up)
    -- z 轴指向相机后方（右手系，视线为 -z）
    local zx, zy, zz = eye.x - target.x, eye.y - target.y, eye.z - target.z
    local zlen = math.sqrt(zx * zx + zy * zy + zz * zz)
    if zlen < 1e-12 then error("Mat4:setLookAt: eye and target coincide") end
    zx, zy, zz = zx / zlen, zy / zlen, zz / zlen

    -- x = normalize(cross(up, z))
    local xx = up.y * zz - up.z * zy
    local xy = up.z * zx - up.x * zz
    local xz = up.x * zy - up.y * zx
    local xlen = math.sqrt(xx * xx + xy * xy + xz * xz)
    if xlen < 1e-12 then error("Mat4:setLookAt: up is parallel to view direction") end
    xx, xy, xz = xx / xlen, xy / xlen, xz / xlen

    -- y = cross(z, x)
    local yx = zy * xz - zz * xy
    local yy = zz * xx - zx * xz
    local yz = zx * xy - zy * xx

    self[1], self[2], self[3], self[4] = xx, yx, zx, 0
    self[5], self[6], self[7], self[8] = xy, yy, zy, 0
    self[9], self[10], self[11], self[12] = xz, yz, zz, 0
    self[13] = -(xx * eye.x + xy * eye.y + xz * eye.z)
    self[14] = -(yx * eye.x + yy * eye.y + yz * eye.z)
    self[15] = -(zx * eye.x + zy * eye.y + zz * eye.z)
    self[16] = 1
    return self
end

-- TRS 组合：平移 t (Vec3)、旋转 q (Quat)、缩放 s（数字或 Vec3，可省略）
function Mat4:setTRS(t, q, s)
    local sx, sy, sz = 1, 1, 1
    if type(s) == "number" then
        sx, sy, sz = s, s, s
    elseif s then
        sx, sy, sz = s.x, s.y, s.z
    end

    local x, y, z, w = q.x, q.y, q.z, q.w
    local xx, yy, zz = x * x, y * y, z * z
    local xy, xz, yz = x * y, x * z, y * z
    local wx, wy, wz = w * x, w * y, w * z

    self[1] = (1 - 2 * (yy + zz)) * sx
    self[2] = (2 * (xy + wz)) * sx
    self[3] = (2 * (xz - wy)) * sx
    self[4] = 0
    self[5] = (2 * (xy - wz)) * sy
    self[6] = (1 - 2 * (xx + zz)) * sy
    self[7] = (2 * (yz + wx)) * sy
    self[8] = 0
    self[9] = (2 * (xz + wy)) * sz
    self[10] = (2 * (yz - wx)) * sz
    self[11] = (1 - 2 * (xx + yy)) * sz
    self[12] = 0
    self[13], self[14], self[15], self[16] = t.x, t.y, t.z, 1
    return self
end

-- 上三阶矩阵的逆转置，用于法线变换。支持一般可逆 3x3，
-- 对含非均匀缩放的 model 矩阵也能保持光照方向正确。
function Mat4:setNormalFromModel(model)
    local a00, a10, a20 = model[1], model[2], model[3]
    local a01, a11, a21 = model[5], model[6], model[7]
    local a02, a12, a22 = model[9], model[10], model[11]

    local c00 = a11 * a22 - a12 * a21
    local c01 = a12 * a20 - a10 * a22
    local c02 = a10 * a21 - a11 * a20
    local c10 = a02 * a21 - a01 * a22
    local c11 = a00 * a22 - a02 * a20
    local c12 = a01 * a20 - a00 * a21
    local c20 = a01 * a12 - a02 * a11
    local c21 = a02 * a10 - a00 * a12
    local c22 = a00 * a11 - a01 * a10

    local det = a00 * c00 + a01 * c01 + a02 * c02
    if math.abs(det) < 1e-12 then
        return self:identity()
    end
    local invDet = 1 / det
    self[1], self[2], self[3], self[4] = c00 * invDet, c10 * invDet, c20 * invDet, 0
    self[5], self[6], self[7], self[8] = c01 * invDet, c11 * invDet, c21 * invDet, 0
    self[9], self[10], self[11], self[12] = c02 * invDet, c12 * invDet, c22 * invDet, 0
    self[13], self[14], self[15], self[16] = 0, 0, 0, 1
    return self
end

function Mat4:setTranslation(x, y, z)
    self:identity()
    self[13], self[14], self[15] = x, y, z
    return self
end

function Mat4.__tostring(m)
    local rows = {}
    for r = 1, 4 do
        rows[r] = string.format("| %8.4f %8.4f %8.4f %8.4f |",
            m[r], m[4 + r], m[8 + r], m[12 + r])
    end
    return table.concat(rows, "\n")
end

return Mat4
