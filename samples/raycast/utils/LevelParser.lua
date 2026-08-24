local LevelParser = {}

-- 辅助函数：将十六进制颜色 (如 "#CC5940") 转换为 LÖVE 适用的 {r, g, b} 数组 (0~1)
local function hexToRGB(hex)
    if not hex then return {1, 1, 1} end
    hex = hex:gsub("#", "")
    local r = tonumber("0x" .. hex:sub(1, 2)) / 255
    local g = tonumber("0x" .. hex:sub(3, 4)) / 255
    local b = tonumber("0x" .. hex:sub(5, 6)) / 255
    return {r, g, b}
end

local function normalizeProperties(properties)
    if not properties then
        return {}
    end

    if #properties > 0 then
        local normalized = {}
        for _, prop in ipairs(properties) do
            normalized[prop.name] = prop.value
        end
        return normalized
    end

    return properties
end

local function normalizePaintingFrame(properties)
    local config = properties.paintingFrame or {}

    local width = tonumber(config.width or properties.paintingWidth) or 0.9
    local height = tonumber(config.height or properties.paintingHeight) or 0.9
    local zOffset = tonumber(config.zOffset or properties.paintingZOffset) or 1.4
    local frameThickness = tonumber(config.frameThickness or properties.frameThickness) or 0.08
    local depthBias = tonumber(config.depthBias or properties.paintingDepthBias) or 0.03
    local scale = tonumber(config.scale or properties.paintingScale) or 1.0

    width = math.max(0.05, width)
    height = math.max(0.05, height)
    scale = math.max(0.05, scale)

    width = math.min(width * scale, 0.98)
    height = math.min(height * scale, 0.98)
    frameThickness = frameThickness * scale

    local maxThickness = math.max(0.001, math.min(width, height) * 0.5 - 0.001)
    frameThickness = math.min(math.max(0.001, frameThickness), maxThickness)
    depthBias = math.max(0, depthBias)

    return {
        scale = scale,
        width = width,
        height = height,
        zOffset = zOffset,
        frameThickness = frameThickness,
        depthBias = depthBias
    }
end

local function buildTileDefinition(ts)
    local properties = normalizeProperties(ts.properties)
    local paintingFrame = normalizePaintingFrame(properties)
    local renderType = properties.renderType
    if not renderType then
        if ts.texture and (
            properties.face ~= nil or
            properties.paintingFrame ~= nil or
            properties.paintingWidth ~= nil or
            properties.paintingHeight ~= nil or
            properties.paintingScale ~= nil
        ) then
            renderType = "painting_wall"
        elseif properties.visible == false then
            renderType = "shadow_only"
        else
            renderType = "solid"
        end
    end

    local passable = (ts.passable == true)
    local solid = (properties.solid ~= nil) and properties.solid or (not passable)
    local blocksMovement = (properties.blocksMovement ~= nil) and properties.blocksMovement or solid
    local raycastBarrier = (properties.raycastBarrier ~= nil) and properties.raycastBarrier
        or (solid and renderType ~= "shadow_only" and (ts.height or 0) >= 1.2)
    local occluder = (properties.occluder ~= nil) and properties.occluder
        or (solid and renderType ~= "shadow_only" and (ts.height or 0) >= 1.2)
    local visible = (properties.visible ~= nil) and properties.visible or (renderType ~= "shadow_only")
    local shadowMode = properties.shadowMode
    if not shadowMode then
        if renderType == "shadow_only" then
            shadowMode = "alpha"
        elseif solid and (ts.height or 0) > 0 then
            shadowMode = "solid"
        else
            shadowMode = "none"
        end
    end

    return {
        id = ts.id,
        name = ts.name,
        kind = properties.kind or "tile",
        color = hexToRGB(ts.color),
        passable = passable,
        solid = solid,
        blocksMovement = blocksMovement,
        raycastBarrier = raycastBarrier,
        occluder = occluder,
        visible = visible,
        shadowMode = shadowMode,
        height = ts.height or 1.0,
        texture = ts.texture,
        paintingFrame = paintingFrame,
        renderType = renderType,
        properties = properties
    }
end

local function createEmptyCell()
    return {
        tileId = 0,
        kind = "empty",
        color = {0, 0, 0},
        passable = true,
        solid = false,
        blocksMovement = false,
        raycastBarrier = false,
        occluder = false,
        visible = false,
        shadowMode = "none",
        height = 0,
        texture = nil,
        paintingFrame = nil,
        renderType = "empty",
        properties = {}
    }
end

local function createCell(tileId, tile)
    if tileId == 0 or not tile then
        return createEmptyCell()
    end

    return {
        tileId = tileId,
        name = tile.name,
        kind = tile.kind,
        color = tile.color,
        passable = tile.passable,
        solid = tile.solid,
        blocksMovement = tile.blocksMovement,
        raycastBarrier = tile.raycastBarrier,
        occluder = tile.occluder,
        visible = tile.visible,
        shadowMode = tile.shadowMode,
        height = tile.height,
        texture = tile.texture,
        paintingFrame = tile.paintingFrame,
        renderType = tile.renderType,
        properties = tile.properties
    }
end

function LevelParser.parse(rawData)
    if not rawData or not rawData.metadata then
        error("LevelParser Error: illegal JSON format or empty.")
    end

    -- 初始化将要返回给引擎的标准化 level 数据
    local level = {
        metadata = rawData.metadata,
        map = {},          -- 2D 数组地图
        player = nil,      -- 玩家初始状态
        sprites = {},      -- 场景内的实体 (如雕像)
        tilesets = {}      -- 图块属性字典
    }

    local width = level.metadata.width
    local height = level.metadata.height

    -- 1. 解析 Tilesets (构建字典，方便引擎 O(1) 查找颜色和高度)
    if rawData.tilesets then
        for _, ts in ipairs(rawData.tilesets) do
            level.tilesets[ts.id] = buildTileDefinition(ts)
        end
    end

    -- 2. 解析 Layers (地图与对象)
    if rawData.layers then
        for _, layer in ipairs(rawData.layers) do
            
            -- [处理图块层]：将 1D 数组转换为 2D 数组
            if layer.type == "tilelayer" then
                for y = 1, height do
                    level.map[y] = {}
                    for x = 1, width do
                        -- 1D 数组索引公式 (Lua 索引从 1 开始)
                        local index = (y - 1) * width + x
                        local tileId = layer.data[index]
                        level.map[y][x] = createCell(tileId, level.tilesets[tileId])
                    end
                end
                
            -- [处理对象层]：提取玩家和场景实体
            elseif layer.type == "objectlayer" and layer.objects then
                for _, obj in ipairs(layer.objects) do
                    
                    if obj.type == "player_spawn" then
                        level.player = {
                            x = obj.x,
                            y = obj.y,
                            -- 引擎底层使用的是弧度制，所以在这里直接将 JSON 里的角度转换好
                            dir = math.rad(obj.properties.angle or 0),
                            fov = math.rad(obj.properties.fov or 60),
                            height = obj.properties.height or 1.2,
                            bobAmount = obj.properties.bobAmount or 0.05,
                            bobSpeed = obj.properties.bobSpeed or 15.0
                        }
                    else
                        -- 其他普通实体（比如 statue_sprite）
                        table.insert(level.sprites, {
                            id = obj.id,
                            type = obj.type,
                            x = obj.x,
                            y = obj.y,
                            properties = obj.properties or {}
                        })
                    end
                end
            end
        end
    end

    -- 安全检查：如果没有找到玩家出生点，给一个默认值防止崩溃
    if not level.player then
        print("Warning: 地图中未找到 player_spawn，使用默认出生点。")
        level.player = { x = 2, y = 2, dir = 0, fov = math.rad(60), height = 1.2 }
    end

    return level
end

return LevelParser
