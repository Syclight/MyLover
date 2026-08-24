local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")
local BinaryMapLoader = require("engine.utils.BinaryMapLoader")

local GameLayer = BaseLayer:extend()

local MOVE_SPEED_METERS = 1.5
local STRAFE_SPEED_METERS = 1.2
local TURN_SPEED = 1.9
local MOUSE_SENSITIVITY = 0.0032
local MAX_PITCH = math.rad(80)
local PLAYER_RADIUS_METERS = 0.22
local DEFAULT_EYE_HEIGHT_METERS = 1.65
local DEFAULT_CEILING_HEIGHT_METERS = 3.0
local FAR_CLIP_METERS = 40.0
local ACTIVE_TILE_MARGIN = 8
local INTERACTION_DISTANCE_METERS = 3.0
local MAX_POINT_LIGHTS = 6
local TAAU_SHARPNESS = 0.16
local STATIC_HISTORY_WEIGHT = 0.18
local HISTORY_MAX_POSITION_DELTA_METERS = 0.0005
local HISTORY_MAX_DIRECTION_DELTA = math.rad(0.03)

local JITTER_SEQUENCE = {
    { 0.0, -0.16666667 },
    { -0.25, 0.16666667 },
    { 0.25, -0.38888889 },
    { -0.375, -0.05555556 },
    { 0.125, 0.27777778 },
    { -0.125, -0.27777778 },
    { 0.375, 0.05555556 },
    { -0.4375, 0.38888889 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function ensureUIState(sceneState)
    sceneState.ui = sceneState.ui or {}
    return sceneState.ui
end

local function syncSceneState(sceneState, minimapData, player, minimapVisible, bigMapVisible, tileSizeMeters, temporalUpscaleEnabled, antiAliasEnabled, interactionState)
    if not sceneState then
        return
    end

    sceneState.minimap = sceneState.minimap or {}
    sceneState.minimap.map = minimapData
    sceneState.minimap.player = player
    local detailVisible = interactionState and interactionState.showDetail == true
    sceneState.minimap.visible = minimapVisible and not detailVisible
    sceneState.minimap.bigVisible = bigMapVisible and not detailVisible
    sceneState.worldConfig = {
        tileSizeMeters = tileSizeMeters
    }
    local uiState = ensureUIState(sceneState)
    uiState.superResolutionEnabled = temporalUpscaleEnabled ~= false
    uiState.antiAliasEnabled = antiAliasEnabled ~= false
    uiState.hoveredInteractable = interactionState and interactionState.hoveredInteractable or nil
    uiState.showDetail = detailVisible
    uiState.detailInteractable = interactionState and interactionState.detailInteractable or nil
end

local function wrapAngleDelta(a, b)
    local delta = a - b
    while delta > math.pi do
        delta = delta - math.pi * 2
    end
    while delta < -math.pi do
        delta = delta + math.pi * 2
    end
    return math.abs(delta)
end

local function getCameraMotion(currentPlayer, previousCamera, tileSizeMeters)
    if not previousCamera then
        return math.huge, math.huge
    end

    local dx = (currentPlayer.x - previousCamera.x) * tileSizeMeters
    local dy = (currentPlayer.y - previousCamera.y) * tileSizeMeters
    local positionDelta = math.sqrt(dx * dx + dy * dy)
    local yawDelta = wrapAngleDelta(currentPlayer.dir, previousCamera.dir)
    local pitchDelta = math.abs((currentPlayer.pitch or 0.0) - (previousCamera.pitch or 0.0))
    local directionDelta = math.max(yawDelta, pitchDelta)
    return positionDelta, directionDelta
end

local function canAccumulateHistory(positionDelta, directionDelta, historyReady)
    if not historyReady then
        return false
    end

    return positionDelta <= HISTORY_MAX_POSITION_DELTA_METERS
        and directionDelta <= HISTORY_MAX_DIRECTION_DELTA
end

local function getHistoryWeight(positionDelta, directionDelta, historyReady)
    if not canAccumulateHistory(positionDelta, directionDelta, historyReady) then
        return 0.0
    end

    local positionFactor = 1.0 - math.min(positionDelta / HISTORY_MAX_POSITION_DELTA_METERS, 1.0)
    local directionFactor = 1.0 - math.min(directionDelta / HISTORY_MAX_DIRECTION_DELTA, 1.0)
    return STATIC_HISTORY_WEIGHT * math.min(positionFactor, directionFactor)
end

local function clearCanvas(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
end

local function resetTemporalHistory(instance)
    if not instance.historyA or not instance.historyB then
        instance.historyReady = false
        instance.previousJitter = { 0.0, 0.0 }
        return
    end

    love.graphics.push("all")
    clearCanvas(instance.historyA)
    clearCanvas(instance.historyB)
    love.graphics.setCanvas()
    love.graphics.pop()

    instance.historyReady = false
    instance.previousJitter = { 0.0, 0.0 }
end

local function hexToRGB(hex)
    if not hex then
        return { 1, 1, 1 }
    end

    local value = hex:gsub("#", "")
    return {
        tonumber("0x" .. value:sub(1, 2)) / 255,
        tonumber("0x" .. value:sub(3, 4)) / 255,
        tonumber("0x" .. value:sub(5, 6)) / 255
    }
end

local function normalizeProperties(properties)
    if not properties then
        return {}
    end

    if #properties > 0 then
        local normalized = {}
        for _, property in ipairs(properties) do
            normalized[property.name] = property.value
        end
        return normalized
    end

    return properties
end

local function buildTilesetLookup(rawTilesets)
    local tilesets = {}
    local maxWallHeight = 0

    tilesets[0] = {
        id = 0,
        color = { 0, 0, 0 },
        height = 0,
        blocksMovement = false,
        visible = false
    }

    for _, rawTileset in ipairs(rawTilesets or {}) do
        if rawTileset.id == 0 then
            goto continue
        end

        local properties = normalizeProperties(rawTileset.properties)
        local height = tonumber(rawTileset.height) or 0
        local passable = rawTileset.passable == true
        local blocksMovement = properties.blocksMovement
        if blocksMovement == nil then
            blocksMovement = not passable
        end

        local visible = properties.visible
        if visible == nil then
            visible = height > 0
        end

        tilesets[rawTileset.id] = {
            id = rawTileset.id,
            color = hexToRGB(rawTileset.color),
            height = height,
            blocksMovement = blocksMovement == true,
            visible = visible == true
        }

        maxWallHeight = math.max(maxWallHeight, height)

        ::continue::
    end

    return tilesets, math.max(maxWallHeight, 0.001)
end

local function parseObjectList(rawObjects)
    local player = nil
    local sprites = {}

    for _, object in ipairs(rawObjects or {}) do
        local properties = normalizeProperties(object.properties)
        if object.type == "player_spawn" then
            player = {
                x = tonumber(object.x) or 2,
                y = tonumber(object.y) or 2,
                dir = math.rad(tonumber(properties.angle) or 0),
                pitch = math.rad(tonumber(properties.pitch) or 0),
                fov = math.rad(tonumber(properties.fov) or 84),
                height = tonumber(properties.height) or 1.28
            }
        else
            table.insert(sprites, {
                id = object.id,
                type = object.type,
                x = tonumber(object.x) or 0,
                y = tonumber(object.y) or 0,
                properties = properties
            })
        end
    end

    if not player then
        player = {
            x = 2.5,
            y = 2.5,
            dir = 0,
            pitch = 0,
            fov = math.rad(84),
            height = 1.28
        }
    end

    return player, sprites
end

local function enableMouseLook(enabled)
    love.mouse.setRelativeMode(enabled)
    love.mouse.setVisible(not enabled)
end

local function mapTileId(mapPackage, x, y)
    local gridX = math.floor(x)
    local gridY = math.floor(y)
    return BinaryMapLoader.getTileId(mapPackage, gridX, gridY)
end

local function mapCell(mapPackage, tilesets, x, y)
    local tileId = mapTileId(mapPackage, x, y)
    if tileId == nil then
        return nil
    end

    return tilesets[tileId] or tilesets[0]
end

local function isBlocked(mapPackage, tilesets, x, y)
    local cell = mapCell(mapPackage, tilesets, x, y)
    if not cell then
        return true
    end

    return cell.blocksMovement == true
end

local function canMove(mapPackage, tilesets, x, y, radius)
    local samples = {
        { x = x, y = y },
        { x = x - radius, y = y },
        { x = x + radius, y = y },
        { x = x, y = y - radius },
        { x = x, y = y + radius },
        { x = x - radius, y = y - radius },
        { x = x + radius, y = y - radius },
        { x = x - radius, y = y + radius },
        { x = x + radius, y = y + radius },
    }

    for _, sample in ipairs(samples) do
        if isBlocked(mapPackage, tilesets, sample.x, sample.y) then
            return false
        end
    end

    return true
end

local function intersectsRect(x, y, radius, centerX, centerY, width, depth)
    local halfWidth = width * 0.5
    local halfDepth = depth * 0.5
    local nearestX = math.max(centerX - halfWidth, math.min(x, centerX + halfWidth))
    local nearestY = math.max(centerY - halfDepth, math.min(y, centerY + halfDepth))
    local dx = x - nearestX
    local dy = y - nearestY
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function canOccupy(mapPackage, tilesets, x, y, radius, tableConfig)
    if not canMove(mapPackage, tilesets, x, y, radius) then
        return false
    end

    if tableConfig and intersectsRect(x, y, radius, tableConfig.x, tableConfig.y, tableConfig.width, tableConfig.depth) then
        return false
    end

    return true
end

local function ensurePassableSpawn(mapPackage, tilesets, player, radius, tableConfig)
    if canOccupy(mapPackage, tilesets, player.x, player.y, radius, tableConfig) then
        return
    end

    local originX = math.floor(player.x)
    local originY = math.floor(player.y)

    for radiusTiles = 1, 12 do
        for gridY = originY - radiusTiles, originY + radiusTiles do
            for gridX = originX - radiusTiles, originX + radiusTiles do
                local isEdge = gridX == originX - radiusTiles
                    or gridX == originX + radiusTiles
                    or gridY == originY - radiusTiles
                    or gridY == originY + radiusTiles
                if isEdge then
                    local candidateX = gridX + 0.5
                    local candidateY = gridY + 0.5
                    if canOccupy(mapPackage, tilesets, candidateX, candidateY, radius, tableConfig) then
                        player.x = candidateX
                        player.y = candidateY
                        return
                    end
                end
            end
        end
    end
end

local function buildMapTexture(mapPackage, originX, originY, width, height, tilesets, maxWallHeight)
    local imageData = love.image.newImageData(width, height)

    for localY = 0, height - 1 do
        for localX = 0, width - 1 do
            local tileId = BinaryMapLoader.getTileId(mapPackage, originX + localX, originY + localY)
            local cell = tilesets[tileId] or tilesets[0]
            local wallHeight = 0
            local color = { 0, 0, 0 }

            if cell and cell.blocksMovement and (cell.height or 0) > 0 then
                wallHeight = (cell.height or 0) / maxWallHeight
                color = cell.color or color
            end

            imageData:setPixel(localX, localY, color[1], color[2], color[3], wallHeight)
        end
    end

    local image = love.graphics.newImage(imageData, { linear = true })
    image:setFilter("nearest", "nearest")
    return image
end

local function extractTableAndPyramid(sprites, tileSizeMeters)
    local metersToGrid = function(value)
        return value / tileSizeMeters
    end

    local tableConfig = {
        x = 12.0,
        y = 9.0,
        width = metersToGrid(1.8),
        depth = metersToGrid(1.1),
        topHeight = 0.82,
        thickness = 0.08,
        legThickness = 0.10,
        color = { 0.42, 0.29, 0.18 }
    }

    local pyramidConfig = {
        x = 12.0,
        y = 9.0,
        size = metersToGrid(0.72),
        height = 0.68,
        color = { 0.83, 0.70, 0.35 }
    }

    for _, object in ipairs(sprites or {}) do
        if object.type == "table" then
            tableConfig.x = object.x or tableConfig.x
            tableConfig.y = object.y or tableConfig.y
            tableConfig.width = metersToGrid(tonumber(object.properties.width) or 1.8)
            tableConfig.depth = metersToGrid(tonumber(object.properties.depth) or 1.1)
            tableConfig.topHeight = tonumber(object.properties.topHeight) or 0.82
            tableConfig.thickness = tonumber(object.properties.thickness) or 0.08
            tableConfig.legThickness = tonumber(object.properties.legThickness) or 0.10
        elseif object.type == "pyramid" then
            pyramidConfig.x = object.x or pyramidConfig.x
            pyramidConfig.y = object.y or pyramidConfig.y
            pyramidConfig.size = metersToGrid(tonumber(object.properties.size) or 0.72)
            pyramidConfig.height = tonumber(object.properties.height) or 0.68
        end
    end

    return tableConfig, pyramidConfig
end

local function buildInteractables(sprites, tileSizeMeters)
    local interactables = {}

    for _, object in ipairs(sprites or {}) do
        if object.type == "point_light" then
            goto continue
        end

        local props = object.properties or {}
        local interactable = {
            id = object.id,
            type = object.type,
            x = object.x,
            y = object.y,
            targetHeight = 0.9,
            desc = props.desc or object.type or "物体",
            detail = props.detail or "这是一个可调查的场景物体。",
            priority = 1
        }

        if object.type == "table" then
            interactable.widthMeters = tonumber(props.width) or 1.8
            interactable.depthMeters = tonumber(props.depth) or 1.1
            interactable.topHeight = tonumber(props.topHeight) or 0.82
            interactable.thickness = tonumber(props.thickness) or 0.08
            interactable.legThickness = tonumber(props.legThickness) or 0.10
            interactable.targetHeight = interactable.topHeight
            interactable.priority = 1
        elseif object.type == "pyramid" then
            interactable.baseHeight = tonumber(props.baseHeight) or 0.82
            interactable.sizeMeters = tonumber(props.size) or 0.72
            interactable.pyramidHeight = tonumber(props.height) or 0.68
            interactable.targetHeight = interactable.baseHeight + interactable.pyramidHeight * 0.55
            interactable.priority = 2
        elseif object.type == "statue_sprite" then
            interactable.priority = 2
            interactable.targetHeight = tonumber(props.height) or 1.2
            interactable.widthMeters = tonumber(props.width) or 0.6
            interactable.depthMeters = tonumber(props.depth) or 0.6
        else
            interactable.priority = tonumber(props.interactionPriority) or 1
            interactable.targetHeight = tonumber(props.targetHeight) or interactable.targetHeight
            interactable.widthMeters = tonumber(props.width) or 0.5
            interactable.depthMeters = tonumber(props.depth) or 0.5
        end

        table.insert(interactables, interactable)

        ::continue::
    end

    return interactables
end

local function buildPointLights(sprites)
    local pointLights = {}

    for _, object in ipairs(sprites or {}) do
        if object.type == "point_light" then
            local props = object.properties or {}
            table.insert(pointLights, {
                x = object.x,
                y = object.y,
                height = tonumber(props.height) or 1.65,
                color = hexToRGB(props.color or "#ffd7a0"),
                intensity = tonumber(props.intensity) or 1.0,
                radius = tonumber(props.radius) or 4.0,
                pulseAmount = tonumber(props.pulseAmount) or 0.0,
                pulseSpeed = tonumber(props.pulseSpeed) or 0.0,
                phase = tonumber(props.phase) or 0.0
            })
        end
    end

    return pointLights
end

local function dot3(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

local function cross3(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function intersectAABB3(roX, roY, roZ, rdX, rdY, rdZ, minX, minY, minZ, maxX, maxY, maxZ)
    local invX = (math.abs(rdX) < 1.0e-6) and math.huge or (1.0 / rdX)
    local invY = (math.abs(rdY) < 1.0e-6) and math.huge or (1.0 / rdY)
    local invZ = (math.abs(rdZ) < 1.0e-6) and math.huge or (1.0 / rdZ)

    local tx1 = (minX - roX) * invX
    local tx2 = (maxX - roX) * invX
    local ty1 = (minY - roY) * invY
    local ty2 = (maxY - roY) * invY
    local tz1 = (minZ - roZ) * invZ
    local tz2 = (maxZ - roZ) * invZ

    local tmin = math.max(math.max(math.min(tx1, tx2), math.min(ty1, ty2)), math.min(tz1, tz2))
    local tmax = math.min(math.min(math.max(tx1, tx2), math.max(ty1, ty2)), math.max(tz1, tz2))

    if tmax < math.max(tmin, 0.0) then
        return nil
    end

    if tmin > 0.0 then
        return tmin
    end

    if tmax > 0.0 then
        return tmax
    end

    return nil
end

local function intersectTriangle3(roX, roY, roZ, rdX, rdY, rdZ, v0, v1, v2)
    local edge1X = v1[1] - v0[1]
    local edge1Y = v1[2] - v0[2]
    local edge1Z = v1[3] - v0[3]
    local edge2X = v2[1] - v0[1]
    local edge2Y = v2[2] - v0[2]
    local edge2Z = v2[3] - v0[3]
    local pvecX, pvecY, pvecZ = cross3(rdX, rdY, rdZ, edge2X, edge2Y, edge2Z)
    local det = dot3(edge1X, edge1Y, edge1Z, pvecX, pvecY, pvecZ)

    if math.abs(det) < 1.0e-6 then
        return nil
    end

    local invDet = 1.0 / det
    local tvecX = roX - v0[1]
    local tvecY = roY - v0[2]
    local tvecZ = roZ - v0[3]
    local u = dot3(tvecX, tvecY, tvecZ, pvecX, pvecY, pvecZ) * invDet
    if u < 0.0 or u > 1.0 then
        return nil
    end

    local qvecX, qvecY, qvecZ = cross3(tvecX, tvecY, tvecZ, edge1X, edge1Y, edge1Z)
    local v = dot3(rdX, rdY, rdZ, qvecX, qvecY, qvecZ) * invDet
    if v < 0.0 or (u + v) > 1.0 then
        return nil
    end

    local t = dot3(edge2X, edge2Y, edge2Z, qvecX, qvecY, qvecZ) * invDet
    if t > 1.0e-6 then
        return t
    end

    return nil
end

local function raycastWallDistance(instance, roX, roY, roZ, rdX, rdY, rdZ)
    if math.abs(rdX) < 1.0e-6 and math.abs(rdY) < 1.0e-6 then
        return math.huge
    end

    local tileSize = instance.tileSizeMeters
    local mapPosX = math.floor(roX / tileSize)
    local mapPosY = math.floor(roY / tileSize)
    local stepX = (rdX < 0.0) and -1 or 1
    local stepY = (rdY < 0.0) and -1 or 1
    local deltaDistX = (math.abs(rdX) < 1.0e-6) and math.huge or math.abs(tileSize / rdX)
    local deltaDistY = (math.abs(rdY) < 1.0e-6) and math.huge or math.abs(tileSize / rdY)
    local sideDistX
    local sideDistY

    if rdX < 0.0 then
        sideDistX = (roX - mapPosX * tileSize) / math.max(math.abs(rdX), 1.0e-6)
    else
        sideDistX = (((mapPosX + 1.0) * tileSize) - roX) / math.max(math.abs(rdX), 1.0e-6)
    end

    if rdY < 0.0 then
        sideDistY = (roY - mapPosY * tileSize) / math.max(math.abs(rdY), 1.0e-6)
    else
        sideDistY = (((mapPosY + 1.0) * tileSize) - roY) / math.max(math.abs(rdY), 1.0e-6)
    end

    for _ = 1, 192 do
        local candidateT
        if sideDistX < sideDistY then
            candidateT = sideDistX
            sideDistX = sideDistX + deltaDistX
            mapPosX = mapPosX + stepX
        else
            candidateT = sideDistY
            sideDistY = sideDistY + deltaDistY
            mapPosY = mapPosY + stepY
        end

        if candidateT > INTERACTION_DISTANCE_METERS then
            break
        end

        local tileId = BinaryMapLoader.getTileId(instance.mapPackage, mapPosX, mapPosY)
        local cell = (tileId ~= nil) and instance.tilesets[tileId] or nil
        if cell and cell.blocksMovement and (cell.height or 0.0) > 0.0 then
            local hitZ = roZ + rdZ * candidateT
            if hitZ >= 0.0 and hitZ <= (cell.height or 0.0) then
                return candidateT
            end
        end
    end

    return math.huge
end

local function intersectTableInteractable(interactable, tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
    local centerX = interactable.x * tileSizeMeters
    local centerY = interactable.y * tileSizeMeters
    local halfWidth = (interactable.widthMeters or 1.8) * 0.5
    local halfDepth = (interactable.depthMeters or 1.1) * 0.5
    local topHeight = interactable.topHeight or 0.82
    local thickness = interactable.thickness or 0.08
    local legThickness = (interactable.legThickness or 0.10) * 0.5
    local legTop = math.max(0.0, topHeight - thickness)
    local bestT = intersectAABB3(
        roX,
        roY,
        roZ,
        rdX,
        rdY,
        rdZ,
        centerX - halfWidth,
        centerY - halfDepth,
        legTop,
        centerX + halfWidth,
        centerY + halfDepth,
        topHeight
    )

    local legCenters = {
        { centerX - halfWidth + legThickness, centerY - halfDepth + legThickness },
        { centerX + halfWidth - legThickness, centerY - halfDepth + legThickness },
        { centerX - halfWidth + legThickness, centerY + halfDepth - legThickness },
        { centerX + halfWidth - legThickness, centerY + halfDepth - legThickness },
    }

    for _, legCenter in ipairs(legCenters) do
        local legT = intersectAABB3(
            roX,
            roY,
            roZ,
            rdX,
            rdY,
            rdZ,
            legCenter[1] - legThickness,
            legCenter[2] - legThickness,
            0.0,
            legCenter[1] + legThickness,
            legCenter[2] + legThickness,
            legTop
        )
        if legT and (not bestT or legT < bestT) then
            bestT = legT
        end
    end

    return bestT
end

local function intersectPyramidInteractable(interactable, tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
    local centerX = interactable.x * tileSizeMeters
    local centerY = interactable.y * tileSizeMeters
    local halfSize = (interactable.sizeMeters or 0.72) * 0.5
    local baseZ = interactable.baseHeight or 0.82
    local apexZ = baseZ + (interactable.pyramidHeight or 0.68)
    local p0 = { centerX - halfSize, centerY - halfSize, baseZ }
    local p1 = { centerX + halfSize, centerY - halfSize, baseZ }
    local p2 = { centerX + halfSize, centerY + halfSize, baseZ }
    local p3 = { centerX - halfSize, centerY + halfSize, baseZ }
    local apex = { centerX, centerY, apexZ }
    local bestT = nil
    local triangles = {
        { p0, p1, apex },
        { p1, p2, apex },
        { p2, p3, apex },
        { p3, p0, apex },
    }

    for _, triangle in ipairs(triangles) do
        local triangleT = intersectTriangle3(roX, roY, roZ, rdX, rdY, rdZ, triangle[1], triangle[2], triangle[3])
        if triangleT and (not bestT or triangleT < bestT) then
            bestT = triangleT
        end
    end

    return bestT
end

local function intersectGenericInteractable(interactable, tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
    local halfWidth = (interactable.widthMeters or 0.5) * 0.5
    local halfDepth = (interactable.depthMeters or interactable.widthMeters or 0.5) * 0.5
    local centerX = interactable.x * tileSizeMeters
    local centerY = interactable.y * tileSizeMeters
    local topHeight = interactable.targetHeight or 1.0
    return intersectAABB3(
        roX,
        roY,
        roZ,
        rdX,
        rdY,
        rdZ,
        centerX - halfWidth,
        centerY - halfDepth,
        0.0,
        centerX + halfWidth,
        centerY + halfDepth,
        topHeight
    )
end

local function resolveHoveredInteractable(instance)
    if not instance.player or not instance.interactables then
        return nil
    end

    local cosPitch = math.cos(instance.player.pitch or 0.0)
    local rdX = math.cos(instance.player.dir) * cosPitch
    local rdY = math.sin(instance.player.dir) * cosPitch
    local rdZ = math.sin(instance.player.pitch or 0.0)
    local roX = instance.player.x * instance.tileSizeMeters
    local roY = instance.player.y * instance.tileSizeMeters
    local roZ = instance.player.height
    local wallDistance = raycastWallDistance(instance, roX, roY, roZ, rdX, rdY, rdZ)
    local bestInteractable = nil
    local bestDistance = math.huge

    for _, interactable in ipairs(instance.interactables) do
        local hitDistance

        if interactable.type == "table" then
            hitDistance = intersectTableInteractable(interactable, instance.tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
        elseif interactable.type == "pyramid" then
            hitDistance = intersectPyramidInteractable(interactable, instance.tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
        else
            hitDistance = intersectGenericInteractable(interactable, instance.tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
        end

        if hitDistance
            and hitDistance <= INTERACTION_DISTANCE_METERS
            and hitDistance < (wallDistance - 0.02) then
            local scoredDistance = hitDistance - interactable.priority * 0.02
            if scoredDistance < bestDistance then
                bestDistance = scoredDistance
                bestInteractable = interactable
            end
        end
    end

    return bestInteractable
end

local function refreshMouseLook(instance)
    enableMouseLook(instance.mouseLookEnabled and not (instance.interactionState and instance.interactionState.showDetail))
end

local function openInteractionDetail(instance, interactable)
    if not interactable then
        return
    end

    instance.interactionState.showDetail = true
    instance.interactionState.detailInteractable = interactable
    refreshMouseLook(instance)
end

local function closeInteractionDetail(instance)
    instance.interactionState.showDetail = false
    instance.interactionState.detailInteractable = nil
    refreshMouseLook(instance)
end

local function getActiveChunkRange(instance, playerX, playerY)
    local mapPackage = instance.mapPackage
    local chunkSize = math.max(1, mapPackage.chunkSize or 32)
    local tileRadius = math.ceil(FAR_CLIP_METERS / math.max(instance.tileSizeMeters, 0.001)) + ACTIVE_TILE_MARGIN
    local chunkRadius = math.max(1, math.ceil(tileRadius / chunkSize))
    local playerChunkX = clamp(math.floor(playerX / chunkSize), 0, mapPackage.chunkColumns - 1)
    local playerChunkY = clamp(math.floor(playerY / chunkSize), 0, mapPackage.chunkRows - 1)

    return {
        minChunkX = clamp(playerChunkX - chunkRadius, 0, mapPackage.chunkColumns - 1),
        maxChunkX = clamp(playerChunkX + chunkRadius, 0, mapPackage.chunkColumns - 1),
        minChunkY = clamp(playerChunkY - chunkRadius, 0, mapPackage.chunkRows - 1),
        maxChunkY = clamp(playerChunkY + chunkRadius, 0, mapPackage.chunkRows - 1),
    }
end

local function rebuildActiveMapWindow(instance, force)
    if not instance.mapPackage or not instance.player then
        return false
    end

    local mapPackage = instance.mapPackage
    local range = getActiveChunkRange(instance, instance.player.x, instance.player.y)
    if not force
        and range.minChunkX == instance.activeChunkMinX
        and range.maxChunkX == instance.activeChunkMaxX
        and range.minChunkY == instance.activeChunkMinY
        and range.maxChunkY == instance.activeChunkMaxY then
        return false
    end

    local chunkSize = mapPackage.chunkSize
    local originX = range.minChunkX * chunkSize
    local originY = range.minChunkY * chunkSize
    local width = math.min(instance.mapWidth - originX, (range.maxChunkX - range.minChunkX + 1) * chunkSize)
    local height = math.min(instance.mapHeight - originY, (range.maxChunkY - range.minChunkY + 1) * chunkSize)

    if instance.mapTexture and instance.mapTexture.release then
        instance.mapTexture:release()
    end

    instance.mapTexture = buildMapTexture(mapPackage, originX, originY, width, height, instance.tilesets, instance.maxWallHeight)
    instance.activeChunkMinX = range.minChunkX
    instance.activeChunkMaxX = range.maxChunkX
    instance.activeChunkMinY = range.minChunkY
    instance.activeChunkMaxY = range.maxChunkY
    instance.activeMapOriginX = originX
    instance.activeMapOriginY = originY
    instance.activeMapWidth = width
    instance.activeMapHeight = height

    BinaryMapLoader.pruneDecodedChunks(mapPackage, range.minChunkX, range.maxChunkX, range.minChunkY, range.maxChunkY)
    return true
end

function GameLayer:new(sceneState)
    local instance = BaseLayer.new(self)
    instance.sceneState = sceneState
    instance.player = nil
    instance.mapPackage = nil
    instance.mapWidth = 0
    instance.mapHeight = 0
    instance.tilesets = nil
    instance.minimapData = nil
    instance.minimapImage = nil
    instance.shader = nil
    instance.resolveShader = nil
    instance.antiAliasShader = nil
    instance.canvas = nil
    instance.historyA = nil
    instance.historyB = nil
    instance.presentCanvas = nil
    instance.mapTexture = nil
    instance.maxWallHeight = 2.6
    instance.ceilingHeight = DEFAULT_CEILING_HEIGHT_METERS
    instance.minimapVisible = true
    instance.bigMapVisible = false
    instance.time = 0
    instance.tableConfig = nil
    instance.pyramidConfig = nil
    instance.tileSizeMeters = 0.5
    instance.moveSpeed = MOVE_SPEED_METERS
    instance.strafeSpeed = STRAFE_SPEED_METERS
    instance.turnSpeed = TURN_SPEED
    instance.playerRadius = PLAYER_RADIUS_METERS
    instance.frameIndex = 0
    instance.historyReady = false
    instance.previousCamera = nil
    instance.previousJitter = { 0.0, 0.0 }
    instance.temporalUpscaleEnabled = true
    instance.antiAliasEnabled = true
    instance.mouseLookEnabled = true
    instance.interactables = nil
    instance.pointLights = nil
    instance.interactionState = {
        hoveredInteractable = nil,
        showDetail = false,
        detailInteractable = nil
    }
    instance.activeChunkMinX = nil
    instance.activeChunkMaxX = nil
    instance.activeChunkMinY = nil
    instance.activeChunkMaxY = nil
    instance.activeMapOriginX = 0
    instance.activeMapOriginY = 0
    instance.activeMapWidth = 0
    instance.activeMapHeight = 0
    return instance
end

function GameLayer:enter()
    ResourceManager:loadManifest("samples/shader_maze/assets/manifest.lua")

    local rawBinary = ResourceManager:getScopeScene("shader_maze_level_1_bin")
    self.mapPackage = BinaryMapLoader.parse(rawBinary)

    local metadata = self.mapPackage.metadata or {}
    self.tileSizeMeters = tonumber(metadata.tileSize) or 0.5
    self.mapWidth = tonumber(metadata.width) or 1
    self.mapHeight = tonumber(metadata.height) or 1
    self.tilesets, self.maxWallHeight = buildTilesetLookup(self.mapPackage.tilesets)

    local player, sprites = parseObjectList(self.mapPackage.objects)
    self.player = player
    self.player.baseHeight = self.player.height or DEFAULT_EYE_HEIGHT_METERS
    self.player.height = self.player.baseHeight
    self.player.pitch = clamp(self.player.pitch or 0.0, -MAX_PITCH, MAX_PITCH)
    self.player.fov = self.player.fov or math.rad(84)

    self.ceilingHeight = DEFAULT_CEILING_HEIGHT_METERS
    self.moveSpeed = MOVE_SPEED_METERS / self.tileSizeMeters
    self.strafeSpeed = STRAFE_SPEED_METERS / self.tileSizeMeters
    self.turnSpeed = TURN_SPEED
    self.playerRadius = PLAYER_RADIUS_METERS / self.tileSizeMeters

    self.tableConfig, self.pyramidConfig = extractTableAndPyramid(sprites, self.tileSizeMeters)
    self.interactables = buildInteractables(sprites, self.tileSizeMeters)
    self.pointLights = buildPointLights(sprites)
    ensurePassableSpawn(self.mapPackage, self.tilesets, self.player, self.playerRadius, self.tableConfig)

    self.minimapImage = BinaryMapLoader.buildMinimapImage(self.mapPackage, self.tilesets)
    self.minimapData = {
        width = self.mapWidth,
        height = self.mapHeight,
        image = self.minimapImage
    }

    rebuildActiveMapWindow(self, true)

    self.shader = ResourceManager:getScopeScene("shader_maze_shader")
    self.resolveShader = ResourceManager:getScopeScene("shader_maze_taau_shader")
    self.antiAliasShader = ResourceManager:getScopeScene("shader_maze_aa_shader")
    self.canvas = ResourceManager:getScopeScene("shader_maze_canvas")
    self.historyA = ResourceManager:getScopeScene("shader_maze_history_a")
    self.historyB = ResourceManager:getScopeScene("shader_maze_history_b")
    self.presentCanvas = ResourceManager:getScopeScene("shader_maze_present")

    self.canvas:setFilter("linear", "linear")
    self.historyA:setFilter("linear", "linear")
    self.historyB:setFilter("linear", "linear")
    self.presentCanvas:setFilter("linear", "linear")

    self.frameIndex = 0
    self.previousCamera = {
        x = self.player.x,
        y = self.player.y,
        dir = self.player.dir,
        pitch = self.player.pitch
    }
    resetTemporalHistory(self)

    syncSceneState(
        self.sceneState,
        self.minimapData,
        self.player,
        self.minimapVisible,
        self.bigMapVisible,
        self.tileSizeMeters,
        self.temporalUpscaleEnabled,
        self.antiAliasEnabled,
        self.interactionState
    )
    refreshMouseLook(self)
end

function GameLayer:update(dt)
    self.time = self.time + dt

    self.interactionState.hoveredInteractable = resolveHoveredInteractable(self)

    if self.interactionState.showDetail then
        self.player.height = self.player.baseHeight
        syncSceneState(
            self.sceneState,
            self.minimapData,
            self.player,
            self.minimapVisible,
            self.bigMapVisible,
            self.tileSizeMeters,
            self.temporalUpscaleEnabled,
            self.antiAliasEnabled,
            self.interactionState
        )
        return
    end

    local forwardX = math.cos(self.player.dir)
    local forwardY = math.sin(self.player.dir)
    local rightX = -forwardY
    local rightY = forwardX

    local moveX = 0
    local moveY = 0

    if love.keyboard.isDown("up") or love.keyboard.isScancodeDown("w") then
        moveX = moveX + forwardX * self.moveSpeed * dt
        moveY = moveY + forwardY * self.moveSpeed * dt
    end
    if love.keyboard.isDown("down") or love.keyboard.isScancodeDown("s") then
        moveX = moveX - forwardX * self.moveSpeed * dt
        moveY = moveY - forwardY * self.moveSpeed * dt
    end
    if love.keyboard.isDown("left") or love.keyboard.isScancodeDown("a") then
        moveX = moveX - rightX * self.strafeSpeed * dt
        moveY = moveY - rightY * self.strafeSpeed * dt
    end
    if love.keyboard.isDown("right") or love.keyboard.isScancodeDown("d") then
        moveX = moveX + rightX * self.strafeSpeed * dt
        moveY = moveY + rightY * self.strafeSpeed * dt
    end

    local nextX = self.player.x + moveX
    local nextY = self.player.y + moveY

    if canOccupy(self.mapPackage, self.tilesets, nextX, self.player.y, self.playerRadius, self.tableConfig) then
        self.player.x = nextX
    end
    if canOccupy(self.mapPackage, self.tilesets, self.player.x, nextY, self.playerRadius, self.tableConfig) then
        self.player.y = nextY
    end

    local moving = math.abs(moveX) > 0.0001 or math.abs(moveY) > 0.0001
    if moving then
        self.player.height = self.player.baseHeight + math.sin(self.time * 8.0) * 0.03
    else
        self.player.height = self.player.baseHeight
    end

    if rebuildActiveMapWindow(self, false) then
        resetTemporalHistory(self)
        self.previousCamera = {
            x = self.player.x,
            y = self.player.y,
            dir = self.player.dir,
            pitch = self.player.pitch
        }
    end

    syncSceneState(
        self.sceneState,
        self.minimapData,
        self.player,
        self.minimapVisible,
        self.bigMapVisible,
        self.tileSizeMeters,
        self.temporalUpscaleEnabled,
        self.antiAliasEnabled,
        self.interactionState
    )
end

function GameLayer:mousemoved(x, y, dx, dy)
    if not self.mouseLookEnabled or not self.player or self.interactionState.showDetail then
        return
    end

    self.player.dir = self.player.dir + dx * MOUSE_SENSITIVITY
    self.player.pitch = clamp(self.player.pitch - dy * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
end

function GameLayer:draw()
    if not self.shader or not self.resolveShader or not self.antiAliasShader or not self.canvas or not self.mapTexture or not self.presentCanvas then
        return
    end

    local canvasWidth = self.canvas:getWidth()
    local canvasHeight = self.canvas:getHeight()
    local outputWidth = self.historyA:getWidth()
    local outputHeight = self.historyA:getHeight()
    local positionDelta, directionDelta = getCameraMotion(self.player, self.previousCamera, self.tileSizeMeters)
    local historyWeight = getHistoryWeight(positionDelta, directionDelta, self.historyReady)
    local allowTemporalAccumulation = self.temporalUpscaleEnabled and historyWeight > 0.0
    local useSubpixelAA = self.antiAliasEnabled and not allowTemporalAccumulation
    local jitter

    if allowTemporalAccumulation then
        jitter = JITTER_SEQUENCE[(self.frameIndex % #JITTER_SEQUENCE) + 1]
    else
        jitter = { 0.0, 0.0 }
    end

    love.graphics.push("all")

    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(self.shader)

    self.shader:send("u_mapTex", self.mapTexture)
    self.shader:send("u_mapSize", { self.activeMapWidth, self.activeMapHeight })
    self.shader:send("u_mapOrigin", { self.activeMapOriginX, self.activeMapOriginY })
    self.shader:send("u_worldMapSize", { self.mapWidth, self.mapHeight })
    self.shader:send("u_tileSize", self.tileSizeMeters)
    self.shader:send("u_renderSize", { canvasWidth, canvasHeight })
    self.shader:send("u_jitter", jitter)
    self.shader:send("u_subpixelAA", useSubpixelAA and 1.0 or 0.0)
    self.shader:send("u_playerPos", { self.player.x * self.tileSizeMeters, self.player.y * self.tileSizeMeters })
    self.shader:send("u_playerDir", self.player.dir)
    self.shader:send("u_playerPitch", self.player.pitch)
    self.shader:send("u_fov", self.player.fov)
    self.shader:send("u_playerHeight", self.player.height)
    self.shader:send("u_wallMaxHeight", self.maxWallHeight)
    self.shader:send("u_ceilingHeight", self.ceilingHeight)

    self.shader:send("u_tablePos", { self.tableConfig.x * self.tileSizeMeters, self.tableConfig.y * self.tileSizeMeters })
    self.shader:send("u_tableSize", { self.tableConfig.width * self.tileSizeMeters, self.tableConfig.depth * self.tileSizeMeters })
    self.shader:send("u_tableTopHeight", self.tableConfig.topHeight)
    self.shader:send("u_tableThickness", self.tableConfig.thickness)
    self.shader:send("u_tableLegThickness", self.tableConfig.legThickness)
    self.shader:send("u_tableColor", self.tableConfig.color)

    self.shader:send("u_pyramidPos", { self.pyramidConfig.x * self.tileSizeMeters, self.pyramidConfig.y * self.tileSizeMeters })
    self.shader:send("u_pyramidSize", self.pyramidConfig.size * self.tileSizeMeters)
    self.shader:send("u_pyramidHeight", self.pyramidConfig.height)
    self.shader:send("u_pyramidColor", self.pyramidConfig.color)

    self.shader:send("u_pointLightCount", math.min(#(self.pointLights or {}), MAX_POINT_LIGHTS))
    for index = 1, MAX_POINT_LIGHTS do
        local light = self.pointLights and self.pointLights[index] or nil
        local suffix = tostring(index - 1)
        if light then
            local pulse = 1.0
            if (light.pulseAmount or 0.0) ~= 0.0 and (light.pulseSpeed or 0.0) ~= 0.0 then
                pulse = 1.0 + math.sin(self.time * light.pulseSpeed + light.phase) * light.pulseAmount
            end
            self.shader:send("u_pointLightPos" .. suffix, {
                light.x * self.tileSizeMeters,
                light.y * self.tileSizeMeters,
                light.height
            })
            self.shader:send("u_pointLightColor" .. suffix, light.color)
            self.shader:send("u_pointLightParams" .. suffix, {
                math.max(0.0, light.intensity * pulse),
                math.max(0.1, light.radius)
            })
        else
            self.shader:send("u_pointLightPos" .. suffix, { 0.0, 0.0, 0.0 })
            self.shader:send("u_pointLightColor" .. suffix, { 0.0, 0.0, 0.0 })
            self.shader:send("u_pointLightParams" .. suffix, { 0.0, 0.1 })
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, canvasWidth, canvasHeight)

    local historySource
    local historyTarget
    if (self.frameIndex % 2) == 0 then
        historySource = self.historyA
        historyTarget = self.historyB
    else
        historySource = self.historyB
        historyTarget = self.historyA
    end

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local scale = math.min(screenWidth / outputWidth, screenHeight / outputHeight)
    local drawWidth = outputWidth * scale
    local drawHeight = outputHeight * scale
    local drawX = (screenWidth - drawWidth) * 0.5
    local drawY = (screenHeight - drawHeight) * 0.5

    if self.temporalUpscaleEnabled then
        local historyUvOffset = {
            (self.previousJitter[1] - jitter[1]) / canvasWidth,
            (self.previousJitter[2] - jitter[2]) / canvasHeight
        }

        love.graphics.setShader()
        love.graphics.setCanvas(historyTarget)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setShader(self.resolveShader)

        self.resolveShader:send("u_lowResTex", self.canvas)
        self.resolveShader:send("u_historyTex", historySource)
        self.resolveShader:send("u_lowResSize", { canvasWidth, canvasHeight })
        self.resolveShader:send("u_outputSize", { outputWidth, outputHeight })
        self.resolveShader:send("u_historyWeight", historyWeight)
        self.resolveShader:send("u_sharpness", TAAU_SHARPNESS)
        self.resolveShader:send("u_historyReady", allowTemporalAccumulation and 1.0 or 0.0)
        self.resolveShader:send("u_historyUvOffset", historyUvOffset)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, outputWidth, outputHeight)
    else
        love.graphics.setShader()
        love.graphics.setCanvas()
    end

    love.graphics.setCanvas(self.presentCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)

    if self.temporalUpscaleEnabled then
        love.graphics.draw(historyTarget, 0, 0)
    else
        love.graphics.draw(self.canvas, 0, 0, 0, outputWidth / canvasWidth, outputHeight / canvasHeight)
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    if self.antiAliasEnabled then
        self.antiAliasShader:send("u_texelSize", { 1.0 / outputWidth, 1.0 / outputHeight })
        love.graphics.setShader(self.antiAliasShader)
    else
        love.graphics.setShader()
    end
    love.graphics.draw(self.presentCanvas, drawX, drawY, 0, scale, scale)
    love.graphics.setShader()
    love.graphics.pop()

    self.historyReady = self.temporalUpscaleEnabled
    self.previousCamera = {
        x = self.player.x,
        y = self.player.y,
        dir = self.player.dir,
        pitch = self.player.pitch
    }
    self.previousJitter = { jitter[1], jitter[2] }
    self.frameIndex = self.frameIndex + 1
end

function GameLayer:keypressed(key)
    if key == "e" then
        if self.interactionState.showDetail then
            closeInteractionDetail(self)
        elseif self.interactionState.hoveredInteractable then
            openInteractionDetail(self, self.interactionState.hoveredInteractable)
        end
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    elseif key == "escape" and self.interactionState.showDetail then
        closeInteractionDetail(self)
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    elseif key == "tab" then
        self.minimapVisible = not self.minimapVisible
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    elseif key == "m" then
        self.bigMapVisible = not self.bigMapVisible
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    elseif key == "u" then
        self.temporalUpscaleEnabled = not self.temporalUpscaleEnabled
        resetTemporalHistory(self)
        self.previousCamera = {
            x = self.player.x,
            y = self.player.y,
            dir = self.player.dir,
            pitch = self.player.pitch
        }
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    elseif key == "i" then
        self.antiAliasEnabled = not self.antiAliasEnabled
        syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
    end
end

function GameLayer:mousepressed(x, y, button)
    if button ~= 1 then
        return
    end

    if self.interactionState.showDetail then
        closeInteractionDetail(self)
    elseif self.interactionState.hoveredInteractable then
        openInteractionDetail(self, self.interactionState.hoveredInteractable)
    end

    syncSceneState(self.sceneState, self.minimapData, self.player, self.minimapVisible, self.bigMapVisible, self.tileSizeMeters, self.temporalUpscaleEnabled, self.antiAliasEnabled, self.interactionState)
end

function GameLayer:pause()
    enableMouseLook(false)
end

function GameLayer:resume()
    refreshMouseLook(self)
end

function GameLayer:exit()
    if self.mapTexture and self.mapTexture.release then
        self.mapTexture:release()
    end
    if self.minimapImage and self.minimapImage.release then
        self.minimapImage:release()
    end

    if self.sceneState and self.sceneState.minimap then
        self.sceneState.minimap.map = nil
        self.sceneState.minimap.player = nil
        self.sceneState.minimap.visible = true
    end

    if self.sceneState then
        self.sceneState.worldConfig = nil
    end

    self.mapTexture = nil
    self.minimapImage = nil
    self.mapPackage = nil
    self.shader = nil
    self.resolveShader = nil
    self.antiAliasShader = nil
    self.canvas = nil
    self.historyA = nil
    self.historyB = nil
    self.presentCanvas = nil
    self.mapWidth = 0
    self.mapHeight = 0
    self.tilesets = nil
    self.minimapData = nil
    self.player = nil
    self.tableConfig = nil
    self.pyramidConfig = nil
    self.interactables = nil
    self.pointLights = nil
    self.interactionState = nil
    self.previousCamera = nil
    self.previousJitter = nil
    self.activeChunkMinX = nil
    self.activeChunkMaxX = nil
    self.activeChunkMinY = nil
    self.activeChunkMaxY = nil
    self.activeMapOriginX = 0
    self.activeMapOriginY = 0
    self.activeMapWidth = 0
    self.activeMapHeight = 0
    enableMouseLook(false)
end

function GameLayer:resize(width, height)
    if not self.historyA then return end
    self.historyA = ResourceManager:resetCanvas("shader_maze_history_a", width, height)
    self.historyB = ResourceManager:resetCanvas("shader_maze_history_b", width, height)
    self.presentCanvas = ResourceManager:resetCanvas("shader_maze_present", width, height)
    self.historyA:setFilter("linear", "linear")
    self.historyB:setFilter("linear", "linear")
    self.presentCanvas:setFilter("linear", "linear")
    resetTemporalHistory(self)
end

return GameLayer
