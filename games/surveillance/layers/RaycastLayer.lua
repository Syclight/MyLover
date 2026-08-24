-- 独立的第一人称光线投射环境层，复用 ShaderMaze 的"渲染技术"（同一套
-- ShaderMaze.glsl + TemporalUpscale + AntiAlias 三 shader、四 canvas 多趟管线），
-- 但完全不依赖、也不修改任何 ShaderMaze 源码：渲染数学在此独立移植，按"单全图窗口"
-- 精简（去掉分块流式/minimap/大地图机器），喂入公寓地图。
--
-- 每帧做交互射线检测：命中 computer 物体且在交互距离内时，写入
-- sceneState.apartment.{canUseComputer, hoverDesc}，供 HUD/Scene 使用。
local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")
local BinaryMapLoader = require("engine.utils.BinaryMapLoader")
local PlayerController = require("games.surveillance.systems.PlayerController")
local InteractionSystem = require("games.surveillance.systems.InteractionSystem")
local PostureSystem = require("games.surveillance.systems.PostureSystem")
local PlacementSystem = require("games.surveillance.systems.PlacementSystem")
local ItemWorldSystem = require("games.surveillance.systems.ItemWorldSystem")
local ApartmentRenderer = require("games.surveillance.rendering.ApartmentRenderer")
local Books = require("games.surveillance.data.books")

local RaycastLayer = BaseLayer:extend()

-- ===== 常量（移植自 ShaderMaze GameLayer）=====
local MOVE_SPEED_METERS = 1.5
local STRAFE_SPEED_METERS = 1.2
local MOUSE_SENSITIVITY = 0.0032
local MAX_PITCH = math.rad(80)
local PLAYER_RADIUS_METERS = 0.22
local DEFAULT_EYE_HEIGHT_METERS = 1.28
local SEATED_EYE_HEIGHT_METERS = 1.12 -- 坐在椅子上的眼高（比站立低）
local DEFAULT_CEILING_HEIGHT_METERS = 3.0
local INTERACTION_DISTANCE_METERS = 1.0 -- 交互距离：约"走到桌前伸手可及"，符合日常感
local CHAIR_SEAT_OFFSET_METERS = 0.6   -- 椅子坐定时位于电脑前方(+y，屏幕朝向侧)的距离
local CHAIR_MOVE_SMOOTHING = 7.0       -- 椅子挪动动画的平滑系数（越大越快）
local PLACE_REACH_METERS = 1.8         -- 放置遥控器的"够得着"距离（沿视线）
local MAX_POINT_LIGHTS = 6
local TAAU_SHARPNESS = 0.16
-- 历史混合权重：越高，抖动越能被多帧平均掉（减少绿屏 shimmer）。
local STATIC_HISTORY_WEIGHT = 0.7
local HISTORY_MAX_POSITION_DELTA_METERS = 0.01
local HISTORY_MAX_DIRECTION_DELTA = math.rad(0.4)

-- 通用写实家具：类型映射 + 地面碰撞足迹（米，local x 宽 / local y 深；吊灯无碰撞）
local FURNITURE_TYPE = { bed = 1, sofa = 2, bookshelf = 3, cabinet = 4, lamp = 6 }
local FURNITURE_FOOTPRINT = {
    [1] = { 1.5, 2.0 },
    [2] = { 1.8, 0.85 },
    [3] = { 0.9, 0.28 },
    [4] = { 0.9, 0.45 },
}
-- 可放置遥控器的家具顶面高度（米）；未列出的（书架/吊灯）不作为放置面
local FURNITURE_TOP_Z = { [1] = 0.50, [2] = 0.52, [4] = 0.90 }
local MAX_FURNITURE = 8
local MAX_PLACED_BOOKS = 12
-- ===== 纯函数辅助（移植）=====
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function hexToRGB(hex)
    if not hex then return { 1, 1, 1 } end
    local value = hex:gsub("#", "")
    return {
        tonumber("0x" .. value:sub(1, 2)) / 255,
        tonumber("0x" .. value:sub(3, 4)) / 255,
        tonumber("0x" .. value:sub(5, 6)) / 255,
    }
end

local function normalizeProperties(properties)
    if not properties then return {} end
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
    tilesets[0] = { id = 0, color = { 0, 0, 0 }, height = 0, blocksMovement = false, visible = false }

    for _, rawTileset in ipairs(rawTilesets or {}) do
        if rawTileset.id ~= 0 then
            local properties = normalizeProperties(rawTileset.properties)
            local height = tonumber(rawTileset.height) or 0
            local passable = rawTileset.passable == true
            local blocksMovement = properties.blocksMovement
            if blocksMovement == nil then blocksMovement = not passable end
            local visible = properties.visible
            if visible == nil then visible = height > 0 end
            tilesets[rawTileset.id] = {
                id = rawTileset.id,
                color = hexToRGB(rawTileset.color),
                height = height,
                blocksMovement = blocksMovement == true,
                visible = visible == true,
            }
            maxWallHeight = math.max(maxWallHeight, height)
        end
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
                height = tonumber(properties.height) or DEFAULT_EYE_HEIGHT_METERS,
            }
        else
            table.insert(sprites, {
                id = object.id,
                type = object.type,
                x = tonumber(object.x) or 0,
                y = tonumber(object.y) or 0,
                properties = properties,
            })
        end
    end
    if not player then
        player = { x = 2.5, y = 2.5, dir = 0, pitch = 0, fov = math.rad(84), height = DEFAULT_EYE_HEIGHT_METERS }
    end
    return player, sprites
end

-- 地图查询 / 碰撞
local function mapCell(mapPackage, tilesets, x, y)
    local tileId = BinaryMapLoader.getTileId(mapPackage, math.floor(x), math.floor(y))
    if tileId == nil then return nil end
    return tilesets[tileId] or tilesets[0]
end

local function isBlocked(mapPackage, tilesets, x, y)
    local cell = mapCell(mapPackage, tilesets, x, y)
    if not cell then return true end
    return cell.blocksMovement == true
end

local function canMove(mapPackage, tilesets, x, y, radius)
    local samples = {
        { x, y }, { x - radius, y }, { x + radius, y }, { x, y - radius }, { x, y + radius },
        { x - radius, y - radius }, { x + radius, y - radius },
        { x - radius, y + radius }, { x + radius, y + radius },
    }
    for _, s in ipairs(samples) do
        if isBlocked(mapPackage, tilesets, s[1], s[2]) then return false end
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
    if not canMove(mapPackage, tilesets, x, y, radius) then return false end
    if tableConfig and intersectsRect(x, y, radius, tableConfig.x, tableConfig.y, tableConfig.width, tableConfig.depth) then
        return false
    end
    return true
end

local function buildMapTexture(mapPackage, width, height, tilesets, maxWallHeight)
    local imageData = love.image.newImageData(width, height)
    for localY = 0, height - 1 do
        for localX = 0, width - 1 do
            local tileId = BinaryMapLoader.getTileId(mapPackage, localX, localY)
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

local function extractTable(sprites, tileSizeMeters)
    local metersToGrid = function(v) return v / tileSizeMeters end
    local tableConfig = {
        x = -100, y = -100, -- 默认放到地图外（无桌子时不可见/不碰撞）
        width = metersToGrid(1.6), depth = metersToGrid(0.8),
        topHeight = 0.8, thickness = 0.06, legThickness = 0.08,
        color = { 0.34, 0.26, 0.18 },
    }
    for _, object in ipairs(sprites or {}) do
        if object.type == "table" then
            tableConfig.x = object.x
            tableConfig.y = object.y
            tableConfig.width = metersToGrid(tonumber(object.properties.width) or 1.6)
            tableConfig.depth = metersToGrid(tonumber(object.properties.depth) or 0.8)
            tableConfig.topHeight = tonumber(object.properties.topHeight) or 0.8
            tableConfig.thickness = tonumber(object.properties.thickness) or 0.06
            tableConfig.legThickness = tonumber(object.properties.legThickness) or 0.08
        end
    end
    return tableConfig
end

-- 字段驱动：任何带 properties.interaction 的对象都登记为可交互体（不再按 type 白名单）。
-- interaction ∈ { "terminal"(接入终端) | "sit"(椅子) | "pickup"(拾取，如遥控器) }。
local function buildInteractables(sprites)
    local interactables = {}
    for _, object in ipairs(sprites or {}) do
        local props = object.properties or {}
        local interaction = props.interaction
        if interaction then
            table.insert(interactables, {
                id = object.id,
                type = object.type,
                interaction = interaction,
                x = object.x,
                y = object.y,
                desc = props.desc or object.type or "物体",
                detail = props.detail or "",
                priority = tonumber(props.interactionPriority) or 1,
                targetHeight = tonumber(props.targetHeight) or 1.0,
                bottomHeight = tonumber(props.bottomHeight) or 0.0,
                widthMeters = tonumber(props.width) or 0.5,
                depthMeters = tonumber(props.depth) or 0.5,
                props = props,
            })
        end
    end
    return interactables
end

local function findSpritePos(sprites, kind)
    for _, object in ipairs(sprites or {}) do
        if object.type == kind then
            return { x = object.x, y = object.y }
        end
    end
    return nil
end

local function findObject(sprites, kind)
    for _, object in ipairs(sprites or {}) do
        if object.type == kind then return object end
    end
    return nil
end

local function findByInteraction(interactables, interaction)
    for _, it in ipairs(interactables or {}) do
        if it.interaction == interaction then return it end
    end
    return nil
end

local function buildPointLights(sprites)
    local pointLights = {}
    for _, object in ipairs(sprites or {}) do
        if object.type == "point_light" then
            local props = object.properties or {}
            table.insert(pointLights, {
                x = object.x, y = object.y,
                height = tonumber(props.height) or 1.65,
                color = hexToRGB(props.color or "#ffd7a0"),
                intensity = tonumber(props.intensity) or 1.0,
                radius = tonumber(props.radius) or 4.0,
                pulseAmount = tonumber(props.pulseAmount) or 0.0,
                pulseSpeed = tonumber(props.pulseSpeed) or 0.0,
                phase = tonumber(props.phase) or 0.0,
            })
        end
    end
    return pointLights
end

-- ===== 射线/相交（移植）=====
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
    if tmax < math.max(tmin, 0.0) then return nil end
    if tmin > 0.0 then return tmin end
    if tmax > 0.0 then return tmax end
    return nil
end

local function raycastWallDistance(instance, roX, roY, roZ, rdX, rdY, rdZ, maxDist)
    maxDist = maxDist or INTERACTION_DISTANCE_METERS
    if math.abs(rdX) < 1.0e-6 and math.abs(rdY) < 1.0e-6 then return math.huge end
    local tileSize = instance.tileSizeMeters
    local mapPosX = math.floor(roX / tileSize)
    local mapPosY = math.floor(roY / tileSize)
    local stepX = (rdX < 0.0) and -1 or 1
    local stepY = (rdY < 0.0) and -1 or 1
    local deltaDistX = (math.abs(rdX) < 1.0e-6) and math.huge or math.abs(tileSize / rdX)
    local deltaDistY = (math.abs(rdY) < 1.0e-6) and math.huge or math.abs(tileSize / rdY)
    local sideDistX, sideDistY
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
        if candidateT > maxDist then break end
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

local function intersectGeneric(interactable, tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
    local halfWidth = (interactable.widthMeters or 0.5) * 0.5
    local halfDepth = (interactable.depthMeters or 0.5) * 0.5
    local centerX = interactable.x * tileSizeMeters
    local centerY = interactable.y * tileSizeMeters
    local topHeight = interactable.targetHeight or 1.0
    local yaw = math.rad(tonumber((interactable.props or {}).yaw) or 0)
    local c, s = math.cos(-yaw), math.sin(-yaw)
    local offsetX, offsetY = roX - centerX, roY - centerY
    local localRoX = offsetX * c - offsetY * s
    local localRoY = offsetX * s + offsetY * c
    local localRdX = rdX * c - rdY * s
    local localRdY = rdX * s + rdY * c
    return intersectAABB3(localRoX, localRoY, roZ, localRdX, localRdY, rdZ,
        -halfWidth, -halfDepth, interactable.bottomHeight or 0.0,
        halfWidth, halfDepth, topHeight)
end

local function resolveHovered(instance)
    if not instance.player or not instance.interactables then return nil end
    local cosPitch = math.cos(instance.player.pitch or 0.0)
    local rdX = math.cos(instance.player.dir) * cosPitch
    local rdY = math.sin(instance.player.dir) * cosPitch
    local rdZ = math.sin(instance.player.pitch or 0.0)
    local roX = instance.player.x * instance.tileSizeMeters
    local roY = instance.player.y * instance.tileSizeMeters
    local roZ = instance.player.height
    -- 墙距上限取所有可交互体里最大的 reach（默认 INTERACTION_DISTANCE）
    local maxReach = INTERACTION_DISTANCE_METERS
    for _, it in ipairs(instance.interactables) do
        maxReach = math.max(maxReach, it.reachMeters or INTERACTION_DISTANCE_METERS)
    end
    local wallDistance = raycastWallDistance(instance, roX, roY, roZ, rdX, rdY, rdZ, maxReach)
    local best
    for _, interactable in ipairs(instance.interactables) do
        local reach = interactable.reachMeters or INTERACTION_DISTANCE_METERS
        local hit = intersectGeneric(interactable, instance.tileSizeMeters, roX, roY, roZ, rdX, rdY, rdZ)
        if hit and hit <= reach and hit < (wallDistance - 0.02) then
            local candidate = { target = interactable, distance = hit }
            if InteractionSystem.isBetterHit(candidate, best) then
                best = candidate
            end
        end
    end
    return best and best.target or nil
end

-- ===== 图层生命周期 =====
function RaycastLayer:new(sceneState)
    local o = BaseLayer.new(self)
    o.sceneState = sceneState
    o.time = 0
    o.temporalUpscaleEnabled = true
    o.antiAliasEnabled = true
    o.mouseLookEnabled = true
    o.frameIndex = 0
    o.historyReady = false
    o.previousCamera = nil
    o.previousJitter = { 0.0, 0.0 }
    o.playerController = PlayerController.new({
        mouseSensitivity = MOUSE_SENSITIVITY,
        maxPitch = MAX_PITCH,
    })
    o.interactionSystem = InteractionSystem.new()
    o.furniturePoseSystem = PostureSystem.new({
        chairSeatOffset = CHAIR_SEAT_OFFSET_METERS,
        chairSmoothing = CHAIR_MOVE_SMOOTHING,
        seatedEyeHeight = SEATED_EYE_HEIGHT_METERS,
        maxPitch = MAX_PITCH,
    })
    o.placementSystem = PlacementSystem.new({ reach = PLACE_REACH_METERS })
    o.itemWorldSystem = ItemWorldSystem.new({
        maxPlacedBooks = MAX_PLACED_BOOKS,
        placementReach = PLACE_REACH_METERS,
    })
    o.renderer = ApartmentRenderer.new({
        sharpness = TAAU_SHARPNESS,
        staticHistoryWeight = STATIC_HISTORY_WEIGHT,
        maxPositionDelta = HISTORY_MAX_POSITION_DELTA_METERS,
        maxDirectionDelta = HISTORY_MAX_DIRECTION_DELTA,
        maxFurniture = MAX_FURNITURE,
        maxPlacedBooks = MAX_PLACED_BOOKS,
        maxPointLights = MAX_POINT_LIGHTS,
    })
    return o
end

function RaycastLayer:enter()
    ResourceManager:loadManifest("games/surveillance/assets/manifest.lua")

    local rawBinary = ResourceManager:getScopeScene("apt_level_bin")
    self.mapPackage = BinaryMapLoader.parse(rawBinary)

    local metadata = self.mapPackage.metadata or {}
    self.tileSizeMeters = tonumber(metadata.tileSize) or 0.5
    self.mapWidth = tonumber(metadata.width) or 1
    self.mapHeight = tonumber(metadata.height) or 1
    self.ceilingHeight = DEFAULT_CEILING_HEIGHT_METERS

    self.tilesets, self.maxWallHeight = buildTilesetLookup(self.mapPackage.tilesets)

    local player, sprites = parseObjectList(self.mapPackage.objects)
    self.player = player
    self.player.baseHeight = self.player.height or DEFAULT_EYE_HEIGHT_METERS
    self.player.pitch = clamp(self.player.pitch or 0.0, -MAX_PITCH, MAX_PITCH)
    self.player.fov = self.player.fov or math.rad(84)
    self.previousPlayerPose = {
        x = self.player.x,
        y = self.player.y,
        height = self.player.height,
        dir = self.player.dir,
        pitch = self.player.pitch,
    }
    self.renderPlayer = {}

    self.moveSpeed = MOVE_SPEED_METERS / self.tileSizeMeters
    self.strafeSpeed = STRAFE_SPEED_METERS / self.tileSizeMeters
    self.playerRadius = PLAYER_RADIUS_METERS / self.tileSizeMeters

    self.tableConfig = extractTable(sprites, self.tileSizeMeters)
    self.interactables = buildInteractables(sprites) -- 字段驱动（properties.interaction）
    self.pointLights = buildPointLights(sprites)
    self.computerPos = findSpritePos(sprites, "computer") -- 显示器位置（光投几何）
    self.chairPos = findSpritePos(sprites, "chair")        -- 椅子位置（光投几何，可被交互挪动）

    -- 按交互类型索引出需要专门行为的可交互体
    self.chairInteractable = findByInteraction(self.interactables, "sit")
    self.remoteInteractable = findByInteraction(self.interactables, "pickup")

    -- 椅子可交互：按 E 把椅子挪到电脑前（模拟坐下、面对屏幕），再按 E 归位。
    self:_setupChairInteraction()

    -- 空调（挂墙，数据驱动）+ 桌面遥控器
    self:_setupClimate(sprites)
    local clockObject = findObject(sprites, "wall_clock")
    if clockObject then
        local props = clockObject.properties or {}
        self.clockConfig = {
            xTiles = clockObject.x,
            wallYMeters = clockObject.y * self.tileSizeMeters,
            height = tonumber(props.height) or 1.72,
        }
    end
    local calendarObject = findObject(sprites, "wall_calendar")
    if calendarObject then
        local props = calendarObject.properties or {}
        self.calendarConfig = {
            xTiles = calendarObject.x,
            wallYMeters = calendarObject.y * self.tileSizeMeters,
            height = tonumber(props.height) or 1.55,
            facing = tonumber(props.facing) or 1,
        }
    end

    -- 通用写实家具实例 + 地面碰撞 + 可放置面
    self.furniture = {}
    self.furnitureColliders = {}
    self.bookshelfMasks = { left = 63, right = 63 }
    -- 每个三位八进制数字保存对应槽位中“书本自身”的样式编号。
    local initialBookStyles = 0
    for index = 1, 6 do initialBookStyles = initialBookStyles + index * 8 ^ (index - 1) end
    self.bookshelfBookStyles = { left = initialBookStyles, right = initialBookStyles }
    self.bookSlots = { left = {}, right = {} }
    self.placedBooks = {}
    self.placeSurfaces = {} -- 放置遥控器的水平面：{x,y(tile中心), w,d(tile足迹), z(米顶面)}
    for _, o in ipairs(sprites) do
        local ft = FURNITURE_TYPE[o.type]
        if ft then
            local yaw = math.rad(tonumber((o.properties or {}).yaw) or 0)
            self.furniture[#self.furniture + 1] = { type = ft, x = o.x, y = o.y, yaw = yaw }
            if o.type == "bookshelf" then
                local shelfKey = o.x < self.mapWidth * 0.5 and "left" or "right"
                self.interactables[#self.interactables + 1] = {
                    id = "bookshelf_" .. tostring(o.id), type = "bookshelf",
                    interaction = "return_book", x = o.x, y = o.y,
                    desc = "书架", priority = 2, bottomHeight = 0.0, targetHeight = 2.0,
                    widthMeters = 0.9, depthMeters = 0.30, reachMeters = 1.35,
                    shelfKey = shelfKey, props = { yaw = (o.properties or {}).yaw or 0 },
                }
                for bookIndex = 1, 6 do
                    local row = math.floor((bookIndex - 1) / 2)
                    local col = (bookIndex - 1) % 2
                    local localX = -0.30 + col * 0.28 + row * 0.05
                    local localY = 0.08
                    local ca, sa = math.cos(yaw), math.sin(yaw)
                    local worldX = o.x + (localX * ca - localY * sa) / self.tileSizeMeters
                    local worldY = o.y + (localX * sa + localY * ca) / self.tileSizeMeters
                    local bottom = row == 0 and 0.04 or (row == 1 and 0.70 or 1.34)
                    local target = {
                        id = "book_" .. tostring(o.id) .. "_" .. tostring(bookIndex),
                        type = "book", interaction = "pickup_book",
                        x = worldX, y = worldY,
                        desc = Books.get(bookIndex).title, priority = 7,
                        bottomHeight = bottom, targetHeight = bottom + 0.54,
                        widthMeters = 0.15, depthMeters = 0.22,
                        reachMeters = 1.25, shelfKey = shelfKey, bookIndex = bookIndex,
                        slotIndex = bookIndex,
                        itemId = "book_" .. tostring(o.id) .. "_" .. tostring(bookIndex),
                    }
                    self.interactables[#self.interactables + 1] = target
                    self.bookSlots[shelfKey][bookIndex] = target
                end
            end
            local fp = FURNITURE_FOOTPRINT[ft]
            if fp then
                local halfW, halfD = fp[1] * 0.5, fp[2] * 0.5
                local ca, sa = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
                local wTiles = ((ca * halfW + sa * halfD) * 2) / self.tileSizeMeters
                local dTiles = ((sa * halfW + ca * halfD) * 2) / self.tileSizeMeters
                self.furnitureColliders[#self.furnitureColliders + 1] = { x = o.x, y = o.y, w = wTiles, d = dTiles }
                local topZ = FURNITURE_TOP_Z[ft]
                if topZ then
                    self.placeSurfaces[#self.placeSurfaces + 1] = { x = o.x, y = o.y, w = wTiles, d = dTiles, z = topZ }
                end
            end
        end
    end

    -- 桌面也是可放置面
    if self.tableConfig and self.tableConfig.x and self.tableConfig.x > -50 then
        self.placeSurfaces[#self.placeSurfaces + 1] = {
            x = self.tableConfig.x, y = self.tableConfig.y,
            w = self.tableConfig.width, d = self.tableConfig.depth,
            z = self.tableConfig.topHeight or 0.78,
        }
    end

    -- 单全图窗口（小地图，无需分块流式）
    self.mapTexture = buildMapTexture(self.mapPackage, self.mapWidth, self.mapHeight, self.tilesets, self.maxWallHeight)
    ResourceManager:register("apt_runtime_map_texture", self.mapTexture, "scene")
    self.activeMapOriginX = 0
    self.activeMapOriginY = 0
    self.activeMapWidth = self.mapWidth
    self.activeMapHeight = self.mapHeight

    self.shader = ResourceManager:getScopeScene("apt_shader")
    self.resolveShader = ResourceManager:getScopeScene("apt_taau")
    self.antiAliasShader = ResourceManager:getScopeScene("apt_aa")
    self.materialAtlas = ResourceManager:getScopeScene("apt_material_atlas")
    self.canvas = ResourceManager:getScopeScene("apt_canvas")
    self.historyA = ResourceManager:getScopeScene("apt_history_a")
    self.historyB = ResourceManager:getScopeScene("apt_history_b")
    self.presentCanvas = ResourceManager:getScopeScene("apt_present")
    self.calendarCanvas = ResourceManager:getScopeScene("apt_calendar_texture")

    self.canvas:setFilter("linear", "linear")
    self.historyA:setFilter("linear", "linear")
    self.historyB:setFilter("linear", "linear")
    self.presentCanvas:setFilter("linear", "linear")
    self.calendarCanvas:setFilter("linear", "linear")
    self.materialAtlas:setFilter("linear", "linear")
    self.materialAtlas:setWrap("repeat", "repeat")

    self.frameIndex = 0
    self.renderer:initialize(self)

    self.sceneState.apartment = self.sceneState.apartment or {}
    self.sceneState.apartment.canUseComputer = false
    self.sceneState.apartment.hoverDesc = nil
end

function RaycastLayer:_canOccupy(x, y)
    if not canOccupy(self.mapPackage, self.tilesets, x, y, self.playerRadius, self.tableConfig) then
        return false
    end
    for _, c in ipairs(self.furnitureColliders or {}) do
        if intersectsRect(x, y, self.playerRadius, c.x, c.y, c.w, c.d) then
            return false
        end
    end
    return true
end

-- 椅子交互初始化：椅子的可交互体来自数据（interaction="sit"），
-- 这里只算"坐定"目标点与状态；其位置每帧由 _updateChair 跟随动画同步。
function RaycastLayer:_setupChairInteraction()
    self.furniturePoseSystem:setupChair(self)
end

function RaycastLayer:_isBlockedAt(x, y)
    return isBlocked(self.mapPackage, self.tilesets, x, y)
end

-- 把椅子挪到电脑前（在原位时调用）。
function RaycastLayer:moveChairToComputer()
    self.furniturePoseSystem:moveChairToComputer(self)
end

-- 把椅子归位（仅在没人坐着时可用）。
function RaycastLayer:returnChairHome()
    self.furniturePoseSystem:returnChairHome(self)
end

-- 坐下：把相机锁到座位、面朝电脑(-y)、眼高下降，并禁用移动。
function RaycastLayer:sitDown()
    if self.sceneState and self.sceneState.transition then
        self.sceneState.transition.alpha = math.max(self.sceneState.transition.alpha or 0, 0.35)
    end
    self.furniturePoseSystem:sitDown(self)
end

-- 起身离开椅子：恢复坐下前的站立姿态（椅子留在电脑前）。
function RaycastLayer:standUp()
    if self.sceneState and self.sceneState.transition then
        self.sceneState.transition.alpha = math.max(self.sceneState.transition.alpha or 0, 0.28)
    end
    self.furniturePoseSystem:standUp(self)
end

-- 椅子位置平滑趋近目标点，并同步可交互体位置（让准星仍能命中移动中的椅子）。
-- 床、沙发和椅子共用姿态恢复数据。
function RaycastLayer:useRest()
    if self.sceneState and self.sceneState.transition then
        self.sceneState.transition.alpha = math.max(self.sceneState.transition.alpha or 0, 0.40)
    end
    self.furniturePoseSystem:useRest(self)
end

function RaycastLayer:pickUpHovered()
    self.itemWorldSystem:pickUpHovered(self)
end

function RaycastLayer:placeBook()
    self.itemWorldSystem:placeBook(self)
end

function RaycastLayer:_updateChair(dt)
    self.furniturePoseSystem:updateChair(self, dt)
end

-- ===== 空调 + 遥控器（数据驱动）=====
-- 空调来自地图对象 air_conditioner（贴墙挂件）；遥控器来自 interaction="pickup" 对象，
-- 拿起后可操作空调。位置/参数全部读自数据，不再硬编码。
function RaycastLayer:_setupClimate(sprites)
    local apt = self.sceneState.apartment
    apt.ac = apt.ac or { power = false, mode = "cool", temp = 26 }

    -- 空调：x/y(贴墙面) 来自对象，y 以 tile 计 -> 米；顶部高度来自属性
    local acObj = findObject(sprites, "air_conditioner")
    if acObj then
        local p = acObj.properties or {}
        self.acConfig = {
            xTiles = acObj.x,
            wallYMeters = acObj.y * self.tileSizeMeters,
            topMeters = tonumber(p.topHeight) or 2.45,
        }
    else
        self.acConfig = nil
    end

    -- 遥控器：复用 buildInteractables 已登记的 pickup 可交互体作为桌面原位。
    -- 静置点带高度 z（米），支持放在桌/床/沙发/柜/地面等任意高度。
    if self.remoteInteractable then
        local p = self.remoteInteractable.props or {}
        local z = tonumber(p.topHeight) or (self.tableConfig.topHeight or 0.78)
        self.remoteRest = { x = self.remoteInteractable.x, y = self.remoteInteractable.y, z = z }
        self.remoteInteractable.targetHeight = z + 0.12
        -- 拾取距离比一般交互更宽松，便于捡起放在地面/床上的遥控器
        self.remoteInteractable.reachMeters = PLACE_REACH_METERS
    end
end

-- 拿起遥控器：从桌面移除可交互体（拿在手上，不再被指向 / 不再渲染在桌上）
function RaycastLayer:pickUpRemote()
    self.itemWorldSystem:pickUpRemote(self)
end

-- 计算准星落点：沿视线找最近的"可放置水平面"（桌/家具顶/地面）交点，需在够得着范围内。
-- 返回 { x, y(tile), z(米) } 或 nil（无有效落点）。
function RaycastLayer:_computePlacement()
    return self.placementSystem:compute(self)
end

-- 把遥控器落定在某处（更新静置点 + 可交互体位置/高度，并恢复可拾取）。
function RaycastLayer:_commitRemote(x, y, z)
    self.itemWorldSystem:commitRemote(self, x, y, z)
end

-- 放在准星落点（自由放置：桌/床/沙发/柜/地面等）
function RaycastLayer:placeRemote()
    self.itemWorldSystem:placeRemote(self)
end

function RaycastLayer:acTogglePower()
    local ac = self.sceneState.apartment.ac
    ac.power = not ac.power
end

function RaycastLayer:acToggleMode()
    local ac = self.sceneState.apartment.ac
    ac.mode = (ac.mode == "cool") and "heat" or "cool"
end

function RaycastLayer:acChangeTemp(delta)
    local ac = self.sceneState.apartment.ac
    ac.temp = clamp((ac.temp or 26) + delta, 16, 30)
end

function RaycastLayer:update(dt)
    local previous = self.previousPlayerPose
    previous.x, previous.y = self.player.x, self.player.y
    previous.height = self.player.height
    previous.dir, previous.pitch = self.player.dir, self.player.pitch
    self.time = self.time + dt
    self:_updateChair(dt)
    local hovered = resolveHovered(self)
    self.interactionSystem:update(self, hovered)
    self.playerController:update(self, dt)
end

function RaycastLayer:mousemoved(x, y, dx, dy)
    self.playerController:mousemoved(self, dx, dy)
end

function RaycastLayer:draw()
    self.renderer:draw(self)
end

function RaycastLayer:drawSnapshot()
    self.renderer:drawSnapshot(self)
end

function RaycastLayer:resize(width, height)
    self.renderer:resize(self, width, height)
end

return RaycastLayer
