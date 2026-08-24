-- SMSHBIN1 二进制网格格式：离线转换（tools/obj2mesh.js）+ 运行时零解析加载。
--
-- 布局（与 BinaryMapLoader 的 SMAPBIN1 同思路：魔数 + JSON 头 + 原始数据流）：
--   [0..7]   魔数 "SMSHBIN1"
--   [8..11]  uint32 LE：JSON 头字节数
--   [12..]   JSON 头 { format, vertexCount, indexCount, indexType, boundingRadius,
--            objects }（objects 为 OBJ 的 o/g/usemtl 分段表，见 ObjLoader.parse 的说明；
--            indexStart 为 1 基，可直接喂 Mesh:setDrawRange 分对象绘制/剔除）
--   之后      顶点流：vertexCount × 8 个 float32 LE（pos3 + uv2 + norm3，
--            与 ObjLoader.VERTEX_FORMAT 一致）
--   之后      索引流：indexCount 个 uint16/uint32 LE，0 基（setVertexMap(Data) 的约定）
--
-- "零解析"的含义：加载时不逐顶点读数——把文件字节经 DataView 直接灌进
-- mesh:setVertices / mesh:setVertexMap（内部一次 memcpy），CPU 成本与顶点数无关。
local json = require("engine.utils.json")
local ObjLoader = require("engine.rendering.ObjLoader")

local MeshBin = {}

MeshBin.MAGIC = "SMSHBIN1"
MeshBin.FORMAT = "pos3_uv2_norm3"

local FLOATS_PER_VERTEX = 8
local VERTEX_STRIDE = FLOATS_PER_VERTEX * 4

-- 把 ObjLoader.parse 的结果编码为二进制串。
-- 与 tools/obj2mesh.js 输出逐字节一致（单元测试用它验证解码器；也可做运行时导出）。
function MeshBin.encode(data)
    local indexType = (data.vertexCount <= 65535) and "uint16" or "uint32"
    local header = json.encode({
        format = MeshBin.FORMAT,
        vertexCount = data.vertexCount,
        indexCount = data.indexCount,
        indexType = indexType,
        boundingRadius = data.boundingRadius,
        objects = data.objects,
    })

    local parts = { MeshBin.MAGIC, love.data.pack("string", "<I4", #header), header }
    local vertexFmt = "<ffffffff"
    for _, v in ipairs(data.vertices) do
        parts[#parts + 1] = love.data.pack("string", vertexFmt, v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8])
    end
    local indexFmt = (indexType == "uint16") and "<I2" or "<I4"
    for _, index in ipairs(data.indices) do
        parts[#parts + 1] = love.data.pack("string", indexFmt, index - 1) -- 转 0 基
    end
    return table.concat(parts)
end

-- 解码：返回 { header, vertexData, indexData }，两个 Data 是对整块缓冲的零拷贝视图。
-- 接受二进制串或 Data（FileData/ByteData）。
function MeshBin.decode(raw)
    local data = raw
    if type(raw) == "string" then
        data = love.data.newByteData(raw)
    end
    local size = data:getSize()
    assert(size > 12, "MeshBin: truncated data")

    local magic = love.data.newDataView(data, 0, #MeshBin.MAGIC):getString()
    assert(magic == MeshBin.MAGIC, "MeshBin: invalid magic")

    local headerLength = love.data.unpack("<I4", data, #MeshBin.MAGIC + 1)
    local headerStart = #MeshBin.MAGIC + 4 -- 0 基偏移
    local header = json.decode(love.data.newDataView(data, headerStart, headerLength):getString())
    assert(header.format == MeshBin.FORMAT,
        "MeshBin: unsupported vertex format '" .. tostring(header.format) .. "'")

    local vertexStart = headerStart + headerLength
    local vertexBytes = header.vertexCount * VERTEX_STRIDE
    local indexStride = (header.indexType == "uint16") and 2 or 4
    local indexBytes = header.indexCount * indexStride
    assert(size >= vertexStart + vertexBytes + indexBytes, "MeshBin: data shorter than header claims")

    return {
        header = header,
        vertexData = love.data.newDataView(data, vertexStart, vertexBytes),
        indexData = love.data.newDataView(data, vertexStart + vertexBytes, indexBytes),
    }
end

-- 解码结果 → LÖVE Mesh（Data 直灌，无逐顶点解析）
function MeshBin.toMesh(decoded, texture)
    local header = decoded.header
    local mesh = love.graphics.newMesh(ObjLoader.VERTEX_FORMAT, header.vertexCount, "triangles", "static")
    mesh:setVertices(decoded.vertexData)
    mesh:setVertexMap(decoded.indexData, header.indexType)
    if texture then mesh:setTexture(texture) end
    return mesh
end

-- 便捷入口：读文件（FileData，不经字符串拷贝）→ decode → toMesh。返回 mesh, header
function MeshBin.load(path, texture)
    local fileData, err = love.filesystem.newFileData(path)
    if not fileData then error("MeshBin: cannot read '" .. path .. "': " .. tostring(err)) end
    local decoded = MeshBin.decode(fileData)
    return MeshBin.toMesh(decoded, texture), decoded.header
end

return MeshBin
