-- 单位立方体网格（边长 1，中心在原点）。
-- 24 顶点（每面 4 个独立顶点，保证每面法线/UV 正确）+ 36 索引。
-- 顶点格式含 3D 位置、UV、法线；环绕方向：从立方体外侧看为 CCW
-- （配合 Camera3D:frontFaceWinding() 决定 setFrontFaceWinding）。
local CubeMesh = {}

local VERTEX_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal", "float", 3 },
}

-- 每面由法线 n 和两个切向轴 u/v 定义，满足 u × v = n（保证 CCW）
local FACES = {
    { n = { 1, 0, 0 },  u = { 0, 0, -1 }, v = { 0, 1, 0 } },  -- +X
    { n = { -1, 0, 0 }, u = { 0, 0, 1 },  v = { 0, 1, 0 } },  -- -X
    { n = { 0, 1, 0 },  u = { 1, 0, 0 },  v = { 0, 0, -1 } }, -- +Y
    { n = { 0, -1, 0 }, u = { 1, 0, 0 },  v = { 0, 0, 1 } },  -- -Y
    { n = { 0, 0, 1 },  u = { 1, 0, 0 },  v = { 0, 1, 0 } },  -- +Z
    { n = { 0, 0, -1 }, u = { -1, 0, 0 }, v = { 0, 1, 0 } },  -- -Z
}

-- 四角在 (u,v) 平面上的符号与 UV（v 朝上 → 纹理 v 反向）
local CORNERS = {
    { -0.5, -0.5, 0, 1 },
    { 0.5, -0.5, 1, 1 },
    { 0.5, 0.5, 1, 0 },
    { -0.5, 0.5, 0, 0 },
}

function CubeMesh.create(texture)
    local vertices = {}
    local indices = {}

    for _, face in ipairs(FACES) do
        local n, u, v = face.n, face.u, face.v
        local base = #vertices
        for _, corner in ipairs(CORNERS) do
            local su, sv, tu, tv = corner[1], corner[2], corner[3], corner[4]
            vertices[#vertices + 1] = {
                n[1] * 0.5 + u[1] * su + v[1] * sv,
                n[2] * 0.5 + u[2] * su + v[2] * sv,
                n[3] * 0.5 + u[3] * su + v[3] * sv,
                tu, tv,
                n[1], n[2], n[3],
            }
        end
        -- 两个三角形：1-2-3, 1-3-4（CCW）
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 2
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 1
        indices[#indices + 1] = base + 3
        indices[#indices + 1] = base + 4
    end

    local mesh = love.graphics.newMesh(VERTEX_FORMAT, vertices, "triangles", "static")
    mesh:setVertexMap(indices)
    if texture then mesh:setTexture(texture) end
    return mesh
end

-- 单位立方体外接球半径（视锥剔除用）
CubeMesh.BOUNDING_RADIUS = math.sqrt(3) * 0.5

return CubeMesh
