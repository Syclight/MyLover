local json = require("engine.utils.json")

local BinaryMapLoader = {}

local MAGIC = "SMAPBIN1"

local function readUInt32LE(data, index)
    local b1 = data:byte(index) or 0
    local b2 = data:byte(index + 1) or 0
    local b3 = data:byte(index + 2) or 0
    local b4 = data:byte(index + 3) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function chunkKey(cx, cy)
    return tostring(cx) .. ":" .. tostring(cy)
end

local function decodeChunk(package, chunkInfo)
    local startByte = package.chunkDataStart + chunkInfo.offset
    local compressed = package.raw:sub(startByte, startByte + chunkInfo.size - 1)
    local raw = love.data.decompress("string", "zlib", compressed)
    local tiles = {}
    local byteIndex = 1
    local tileCount = chunkInfo.width * chunkInfo.height

    for i = 1, tileCount do
        local lo = raw:byte(byteIndex) or 0
        local hi = raw:byte(byteIndex + 1) or 0
        tiles[i] = lo + hi * 256
        byteIndex = byteIndex + 2
    end

    chunkInfo.tiles = tiles
    package.decodedChunks[chunkKey(chunkInfo.cx, chunkInfo.cy)] = chunkInfo
    return chunkInfo
end

function BinaryMapLoader.parse(raw)
    assert(type(raw) == "string", "BinaryMapLoader.parse expects raw binary string")
    assert(raw:sub(1, #MAGIC) == MAGIC, "BinaryMapLoader: invalid magic")

    local headerLength = readUInt32LE(raw, #MAGIC + 1)
    local headerStart = #MAGIC + 5
    local headerStop = headerStart + headerLength - 1
    local headerJson = raw:sub(headerStart, headerStop)
    local header = json.decode(headerJson)
    local chunksByKey = {}

    for _, chunk in ipairs(header.chunks or {}) do
        chunksByKey[chunkKey(chunk.cx, chunk.cy)] = chunk
    end

    return {
        raw = raw,
        metadata = header.metadata,
        tilesets = header.tilesets or {},
        objects = header.objects or {},
        chunkSize = header.chunkSize or 32,
        chunkColumns = header.chunkColumns or 1,
        chunkRows = header.chunkRows or 1,
        chunks = header.chunks or {},
        chunksByKey = chunksByKey,
        chunkDataStart = headerStop + 1,
        decodedChunks = {}
    }
end

function BinaryMapLoader.getChunk(package, cx, cy)
    local key = chunkKey(cx, cy)
    local cached = package.decodedChunks[key]
    if cached then
        return cached
    end

    local chunkInfo = package.chunksByKey[key]
    if not chunkInfo then
        return nil
    end

    return decodeChunk(package, chunkInfo)
end

function BinaryMapLoader.getTileId(package, x, y)
    if x < 0 or y < 0 or x >= package.metadata.width or y >= package.metadata.height then
        return nil
    end

    local chunkSize = package.chunkSize
    local cx = math.floor(x / chunkSize)
    local cy = math.floor(y / chunkSize)
    local chunk = BinaryMapLoader.getChunk(package, cx, cy)
    if not chunk then
        return 0
    end

    local localX = x - cx * chunkSize
    local localY = y - cy * chunkSize
    if localX < 0 or localY < 0 or localX >= chunk.width or localY >= chunk.height then
        return 0
    end

    return chunk.tiles[localY * chunk.width + localX + 1] or 0
end

function BinaryMapLoader.buildMinimapImage(package, tilesetLookup)
    local width = package.metadata.width
    local height = package.metadata.height
    local imageData = love.image.newImageData(width, height)

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local tileId = BinaryMapLoader.getTileId(package, x, y)
            local tile = tilesetLookup[tileId]
            if tile and tile.visible then
                imageData:setPixel(x, y, tile.color[1], tile.color[2], tile.color[3], 1.0)
            else
                imageData:setPixel(x, y, 0.16, 0.16, 0.16, 0.55)
            end
        end
    end

    local image = love.graphics.newImage(imageData, { linear = true })
    image:setFilter("nearest", "nearest")
    return image
end

function BinaryMapLoader.pruneDecodedChunks(package, minChunkX, maxChunkX, minChunkY, maxChunkY)
    for key, chunk in pairs(package.decodedChunks) do
        if chunk.cx < minChunkX or chunk.cx > maxChunkX or chunk.cy < minChunkY or chunk.cy > maxChunkY then
            package.decodedChunks[key] = nil
            chunk.tiles = nil
        end
    end
end

return BinaryMapLoader
