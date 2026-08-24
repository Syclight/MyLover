-- Wavefront OBJ 解析器 → LÖVE Mesh（自定义顶点格式 pos3 + uv2 + norm3）。
--
-- 约定与 CubeMesh 一致：三角形从外侧看为 CCW（OBJ 标准即如此），
-- UV 的 v 轴翻转（OBJ 原点在左下，LÖVE 贴图原点在左上）。
-- 支持 v/vt/vn、f 的四种引用写法（v、v/vt、v//vn、v/vt/vn）、负数相对索引、
-- 任意多边形面（扇形三角化）。无 vn 时按面法线补齐。
-- Blender 兼容：o/g 分段成对象表（name/material/indexStart/indexCount/center/boundingRadius，
-- 配合 Mesh:setDrawRange 分对象绘制/剔除）；mtllib/usemtl/s 等行容错忽略。
--
-- 运行时热加载文本 OBJ 只用于开发迭代；发布路径走 tools/obj2mesh.js 离线转出的
-- SMSHBIN1 二进制（engine/rendering/MeshBin.lua），加载零解析开销。
local ObjLoader = {}

-- 与 CubeMesh 相同的顶点格式；MeshBin/obj2mesh.js 的字节布局都以此为准（8 float/顶点）
ObjLoader.VERTEX_FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal", "float", 3 },
}

local function resolveIndex(index, count)
    if index < 0 then return count + index + 1 end
    return index
end

-- 解析 OBJ 文本。返回：
--   { vertices = { {x,y,z,u,v,nx,ny,nz}, ... },  -- 去重后的顶点表（newMesh 直接可用）
--     indices = { 1-based ... },                  -- 三角形索引（setVertexMap 直接可用）
--     vertexCount, indexCount, boundingRadius,    -- 包围半径以模型原点为中心（视锥剔除用）
--     objects = { { name, indexStart, indexCount, -- o/g 分段（indexStart 为 1 基，
--                    center = {x,y,z},            --  可直接喂 Mesh:setDrawRange）
--                    boundingRadius }, ... } }    -- 包围球以对象 AABB 中心为球心
function ObjLoader.parse(text)
    assert(type(text) == "string", "ObjLoader.parse expects OBJ source text")
    local positions, uvs, normals = {}, {}, {}
    local vertices, indices = {}, {}
    local dedupe = {}       -- "v/vt/vn" → 顶点表下标
    local radiusSq = 0

    local objects = {}
    local current = nil
    local currentMaterial = nil

    local function finishObject()
        if not current then return end
        current.indexCount = #indices - current.indexStart + 1
        if current.indexCount > 0 then
            local cx = (current.minX + current.maxX) * 0.5
            local cy = (current.minY + current.maxY) * 0.5
            local cz = (current.minZ + current.maxZ) * 0.5
            local dx = current.maxX - cx
            local dy = current.maxY - cy
            local dz = current.maxZ - cz
            current.center = { cx, cy, cz }
            current.boundingRadius = math.sqrt(dx * dx + dy * dy + dz * dz)
            current.minX, current.minY, current.minZ = nil, nil, nil
            current.maxX, current.maxY, current.maxZ = nil, nil, nil
            objects[#objects + 1] = current
        end
        current = nil
    end

    local function beginObject(name)
        finishObject()
        current = {
            name = name,
            material = currentMaterial,
            indexStart = #indices + 1,
            minX = math.huge, minY = math.huge, minZ = math.huge,
            maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge,
        }
    end

    local function setMaterial(name)
        currentMaterial = name
        if current and #indices >= current.indexStart then
            beginObject(current.name)
        elseif current then
            current.material = name
        end
    end

    local function addVertex(vi, ti, ni, faceNormal)
        local key
        if ni then
            key = vi .. "/" .. (ti or 0) .. "/" .. ni
        else
            -- 无 vn 的面用面法线；不同面即使共享位置也不合并（硬边）
            key = vi .. "/" .. (ti or 0) .. "/f" .. #indices
        end
        local existing = dedupe[key]
        if existing then return existing end

        local p = positions[vi]
        if not p then error("ObjLoader: face references missing vertex " .. tostring(vi)) end
        local t = ti and uvs[ti] or nil
        local n = ni and normals[ni] or faceNormal

        vertices[#vertices + 1] = {
            p[1], p[2], p[3],
            t and t[1] or 0, t and (1 - t[2]) or 0, -- v 翻转
            n[1], n[2], n[3],
        }
        local index = #vertices
        dedupe[key] = index
        return index
    end

    local corners = {} -- 复用的面角点缓冲 { {vi, ti, ni}, ... }

    for line in text:gmatch("[^\r\n]+") do
        local head, rest = line:match("^%s*(%S+)%s+(.*)$")
        if head == "v" then
            local x, y, z = rest:match("(%-?[%d%.eE%-+]+)%s+(%-?[%d%.eE%-+]+)%s+(%-?[%d%.eE%-+]+)")
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            positions[#positions + 1] = { x, y, z }
            local d = x * x + y * y + z * z
            if d > radiusSq then radiusSq = d end
        elseif head == "vt" then
            local u, v = rest:match("(%-?[%d%.eE%-+]+)%s+(%-?[%d%.eE%-+]+)")
            uvs[#uvs + 1] = { tonumber(u), tonumber(v) }
        elseif head == "vn" then
            local x, y, z = rest:match("(%-?[%d%.eE%-+]+)%s+(%-?[%d%.eE%-+]+)%s+(%-?[%d%.eE%-+]+)")
            normals[#normals + 1] = { tonumber(x), tonumber(y), tonumber(z) }
        elseif head == "o" or head == "g" then
            beginObject(rest:match("^%s*(.-)%s*$"))
        elseif head == "usemtl" then
            setMaterial(rest:match("^%s*(.-)%s*$"))
        elseif head == "f" then
            if not current then beginObject("default") end
            local count = 0
            for corner in rest:gmatch("%S+") do
                local vi, ti, ni = corner:match("^(%-?%d+)/?(%-?%d*)/?(%-?%d*)$")
                count = count + 1
                local slot = corners[count]
                if not slot then slot = {}; corners[count] = slot end
                slot[1] = resolveIndex(tonumber(vi), #positions)
                slot[2] = ti ~= "" and resolveIndex(tonumber(ti), #uvs) or nil
                slot[3] = ni ~= "" and resolveIndex(tonumber(ni), #normals) or nil
            end
            if count >= 3 then
                -- 当前对象的 AABB 吸收本面所有角点（重复角点无影响）
                for i = 1, count do
                    local p = positions[corners[i][1]]
                    if p then
                        if p[1] < current.minX then current.minX = p[1] end
                        if p[2] < current.minY then current.minY = p[2] end
                        if p[3] < current.minZ then current.minZ = p[3] end
                        if p[1] > current.maxX then current.maxX = p[1] end
                        if p[2] > current.maxY then current.maxY = p[2] end
                        if p[3] > current.maxZ then current.maxZ = p[3] end
                    end
                end
                -- 面法线（仅当角点缺 vn 时使用）：前三个角点叉积
                local faceNormal
                if not corners[1][3] then
                    local a = positions[corners[1][1]]
                    local b = positions[corners[2][1]]
                    local c = positions[corners[3][1]]
                    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
                    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
                    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                    local len = math.sqrt(nx * nx + ny * ny + nz * nz)
                    if len > 1e-12 then nx, ny, nz = nx / len, ny / len, nz / len end
                    faceNormal = { nx, ny, nz }
                end
                -- 扇形三角化，保持 OBJ 的 CCW 环绕
                local first = addVertex(corners[1][1], corners[1][2], corners[1][3], faceNormal)
                local prev = addVertex(corners[2][1], corners[2][2], corners[2][3], faceNormal)
                for i = 3, count do
                    local current = addVertex(corners[i][1], corners[i][2], corners[i][3], faceNormal)
                    indices[#indices + 1] = first
                    indices[#indices + 1] = prev
                    indices[#indices + 1] = current
                    prev = current
                end
            end
        end
    end

    finishObject()

    return {
        vertices = vertices,
        indices = indices,
        vertexCount = #vertices,
        indexCount = #indices,
        boundingRadius = math.sqrt(radiusSq),
        objects = objects,
    }
end

-- 解析结果 → LÖVE Mesh（调用方负责 release；不进 ResourceManager 的手动资源）
function ObjLoader.toMesh(data, texture)
    local mesh = love.graphics.newMesh(ObjLoader.VERTEX_FORMAT, data.vertices, "triangles", "static")
    mesh:setVertexMap(data.indices)
    if texture then mesh:setTexture(texture) end
    return mesh
end

-- 便捷入口：读文件 → parse → toMesh。返回 mesh, parsed
function ObjLoader.load(path, texture)
    local text, err = love.filesystem.read(path)
    if not text then error("ObjLoader: cannot read '" .. path .. "': " .. tostring(err)) end
    local data = ObjLoader.parse(text)
    return ObjLoader.toMesh(data, texture), data
end

return ObjLoader
