local ResourceManager = require("engine.managers.ResourceManager")
local Inventory = require("games.surveillance.gameplay.Inventory")
local Fuc = require("engine.utils.Fuc")
local GpuProfiler = require("engine.utils.GpuProfiler")
local Timestep = require("engine.utils.Timestep")
local Books = require("games.surveillance.data.books")
local GameClock = require("games.surveillance.gameplay.GameClock")
local CalendarTexture = require("games.surveillance.rendering.CalendarTexture")

local ApartmentRenderer = {}
ApartmentRenderer.__index = ApartmentRenderer

local JITTER_SEQUENCE = {
    { 0.0, -0.16666667 }, { -0.25, 0.16666667 }, { 0.25, -0.38888889 },
    { -0.375, -0.05555556 }, { 0.125, 0.27777778 }, { -0.125, -0.27777778 },
    { 0.375, 0.05555556 }, { -0.4375, 0.38888889 },
}

local function wrapAngleDelta(a, b)
    local delta = a - b
    while delta > math.pi do delta = delta - math.pi * 2 end
    while delta < -math.pi do delta = delta + math.pi * 2 end
    return math.abs(delta)
end

local function cameraMotion(player, previous, tileSize)
    if not previous then return math.huge, math.huge end
    local dx, dy = (player.x - previous.x) * tileSize, (player.y - previous.y) * tileSize
    local position = math.sqrt(dx * dx + dy * dy)
    return position, math.max(wrapAngleDelta(player.dir, previous.dir), math.abs((player.pitch or 0) - (previous.pitch or 0)))
end

local function cameraState(player, tileSize, width, height)
    local cp, sp = math.cos(player.pitch), math.sin(player.pitch)
    local cy, sy = math.cos(player.dir), math.sin(player.dir)
    return {
        x = player.x, y = player.y, dir = player.dir, pitch = player.pitch,
        position = { player.x * tileSize, player.y * tileSize, player.height },
        forward = { cy * cp, sy * cp, sp }, right = { -sy, cy, 0 },
        up = { -sp * cy, -sp * sy, cp },
        tanHalfFov = math.tan(player.fov * 0.5),
        invAspect = height / math.max(width, 1),
    }
end

function ApartmentRenderer.new(config)
    return setmetatable({
        sharpness = config.sharpness,
        staticHistoryWeight = config.staticHistoryWeight,
        maxPositionDelta = config.maxPositionDelta,
        maxDirectionDelta = config.maxDirectionDelta,
        maxFurniture = config.maxFurniture,
        maxPlacedBooks = config.maxPlacedBooks,
        maxPointLights = config.maxPointLights,
    }, ApartmentRenderer)
end

function ApartmentRenderer:historyWeight(positionDelta, directionDelta, ready)
    if not ready or positionDelta > self.maxPositionDelta or directionDelta > self.maxDirectionDelta then return 0 end
    local p = 1 - math.min(positionDelta / self.maxPositionDelta, 1)
    local d = 1 - math.min(directionDelta / self.maxDirectionDelta, 1)
    return self.staticHistoryWeight * math.min(p, d)
end

function ApartmentRenderer:resetHistory(world)
    if not world.historyA or not world.historyB then
        world.historyReady, world.previousJitter = false, { 0, 0 }
        return
    end
    love.graphics.push("all")
    for _, canvas in ipairs({ world.historyA, world.historyB }) do
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 1)
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    world.historyReady, world.previousJitter = false, { 0, 0 }
end

function ApartmentRenderer:initialize(world)
    world.previousCamera = cameraState(world.player, world.tileSizeMeters, world.canvas:getWidth(), world.canvas:getHeight())
    self:resetHistory(world)
end

local function sendOptionalPosition(shader, prefix, object, tileSize)
    if object then
        Fuc.safeSend(shader, prefix .. "Pos", { object.x * tileSize, object.y * tileSize })
        Fuc.safeSend(shader, prefix .. "Present", 1.0)
    else
        Fuc.safeSend(shader, prefix .. "Pos", { -1000, -1000 })
        Fuc.safeSend(shader, prefix .. "Present", 0.0)
    end
end

function ApartmentRenderer:uploadScene(world, shader, camera, renderPlayer, jitter, width, height)
    Fuc.safeSend(shader, "u_mapTex", world.mapTexture)
    Fuc.safeSend(shader, "u_materialAtlas", world.materialAtlas)
    Fuc.safeSend(shader, "u_mapSize", { world.activeMapWidth, world.activeMapHeight })
    Fuc.safeSend(shader, "u_mapOrigin", { world.activeMapOriginX, world.activeMapOriginY })
    Fuc.safeSend(shader, "u_worldMapSize", { world.mapWidth, world.mapHeight })
    Fuc.safeSend(shader, "u_tileSize", world.tileSizeMeters)
    Fuc.safeSend(shader, "u_renderSize", { width, height })
    Fuc.safeSend(shader, "u_jitter", jitter)
    Fuc.safeSend(shader, "u_playerPos", { camera.position[1], camera.position[2] })
    Fuc.safeSend(shader, "u_cameraForward", camera.forward)
    Fuc.safeSend(shader, "u_cameraRight", camera.right)
    Fuc.safeSend(shader, "u_cameraUp", camera.up)
    Fuc.safeSend(shader, "u_tanHalfFov", camera.tanHalfFov)
    Fuc.safeSend(shader, "u_invAspect", camera.invAspect)
    Fuc.safeSend(shader, "u_playerHeight", renderPlayer.height)
    Fuc.safeSend(shader, "u_wallMaxHeight", world.maxWallHeight)
    Fuc.safeSend(shader, "u_ceilingHeight", world.ceilingHeight)

    local tableConfig = world.tableConfig
    Fuc.safeSend(shader, "u_tablePos", { tableConfig.x * world.tileSizeMeters, tableConfig.y * world.tileSizeMeters })
    Fuc.safeSend(shader, "u_tableSize", { tableConfig.width * world.tileSizeMeters, tableConfig.depth * world.tileSizeMeters })
    Fuc.safeSend(shader, "u_tableTopHeight", tableConfig.topHeight)
    Fuc.safeSend(shader, "u_tableThickness", tableConfig.thickness)
    Fuc.safeSend(shader, "u_tableLegThickness", tableConfig.legThickness)
    Fuc.safeSend(shader, "u_tableColor", tableConfig.color)
    Fuc.safeSend(shader, "u_pyramidPos", { -1000, -1000 })
    Fuc.safeSend(shader, "u_pyramidSize", 0)
    Fuc.safeSend(shader, "u_pyramidHeight", 0)
    Fuc.safeSend(shader, "u_pyramidColor", { 0, 0, 0 })
    sendOptionalPosition(shader, "u_computer", world.computerPos, world.tileSizeMeters)
    sendOptionalPosition(shader, "u_chair", world.chairPos, world.tileSizeMeters)

    local ac, acState = world.sceneState.apartment.ac, 0
    if ac and ac.power then acState = ac.mode == "heat" and 2 or 1 end
    if world.acConfig then
        Fuc.safeSend(shader, "u_acPos", { world.acConfig.xTiles * world.tileSizeMeters, world.acConfig.wallYMeters })
        Fuc.safeSend(shader, "u_acPresent", 1)
        Fuc.safeSend(shader, "u_acTopHeight", world.acConfig.topMeters)
        Fuc.safeSend(shader, "u_acState", acState)
    else Fuc.safeSend(shader, "u_acPresent", 0) end

    if world.clockConfig then
        local hands = GameClock.handDirections(world.sceneState.clock)
        Fuc.safeSend(shader, "u_clockPos", {
            world.clockConfig.xTiles * world.tileSizeMeters,
            world.clockConfig.wallYMeters,
            world.clockConfig.height,
        })
        Fuc.safeSend(shader, "u_clockHourHand", hands.hour)
        Fuc.safeSend(shader, "u_clockMinuteHand", hands.minute)
        Fuc.safeSend(shader, "u_clockPresent", 1)
    else
        Fuc.safeSend(shader, "u_clockPresent", 0)
    end

    if world.calendarConfig then
        Fuc.safeSend(shader, "u_calendarPos", {
            world.calendarConfig.xTiles * world.tileSizeMeters,
            world.calendarConfig.wallYMeters,
            world.calendarConfig.height,
        })
        Fuc.safeSend(shader, "u_calendarFacing", world.calendarConfig.facing)
        Fuc.safeSend(shader, "u_calendarTex", world.calendarCanvas)
        Fuc.safeSend(shader, "u_calendarPresent", 1)
    else
        Fuc.safeSend(shader, "u_calendarPresent", 0)
    end

    local inventory = world.sceneState.inventory
    local remoteSelected = Inventory.isSelected(inventory, "ac_remote")
    local remoteSpot = remoteSelected and world.remotePlacement or world.remoteRest
    if ((not Inventory.has(inventory, "ac_remote")) or (remoteSelected and world.remotePlacement)) and remoteSpot then
        Fuc.safeSend(shader, "u_remotePos", { remoteSpot.x * world.tileSizeMeters, remoteSpot.y * world.tileSizeMeters })
        Fuc.safeSend(shader, "u_remoteTopHeight", remoteSpot.z)
        Fuc.safeSend(shader, "u_remotePresent", 1)
    else Fuc.safeSend(shader, "u_remotePresent", 0) end

    Fuc.safeSend(shader, "u_furnitureCount", math.min(#world.furniture, self.maxFurniture))
    Fuc.safeSend(shader, "u_bookshelfMaskLeft", world.bookshelfMasks.left)
    Fuc.safeSend(shader, "u_bookshelfMaskRight", world.bookshelfMasks.right)
    Fuc.safeSend(shader, "u_bookshelfBookStylesLeft", world.bookshelfBookStyles.left)
    Fuc.safeSend(shader, "u_bookshelfBookStylesRight", world.bookshelfBookStyles.right)
    for index = 1, 6 do
        Fuc.safeSend(shader, "u_bookColor" .. index, Books.color(index))
    end
    Fuc.safeSend(shader, "u_placedBookCount", math.min(#world.placedBooks, self.maxPlacedBooks))
    for index = 1, self.maxPlacedBooks do
        local entry = world.placedBooks[index]
        local data = entry and { entry.x * world.tileSizeMeters, entry.y * world.tileSizeMeters, entry.z, entry.item.bookIndex or 1 }
            or { 0, 0, -1000, 1 }
        Fuc.safeSend(shader, "u_placedBook" .. index - 1, data)
    end
    local heldBook = Inventory.selected(inventory)
    if heldBook and heldBook.icon == "book" and world.bookPlacement and not world.sceneState.apartment.bookShelfTarget then
        Fuc.safeSend(shader, "u_bookPreview", {
            world.bookPlacement.x * world.tileSizeMeters, world.bookPlacement.y * world.tileSizeMeters,
            world.bookPlacement.z, heldBook.bookIndex or 1,
        })
    else Fuc.safeSend(shader, "u_bookPreview", { 0, 0, -1000, -1 }) end

    for index = 1, self.maxFurniture do
        local furniture = world.furniture[index]
        Fuc.safeSend(shader, "u_furniture" .. index - 1, furniture and {
            furniture.x * world.tileSizeMeters, furniture.y * world.tileSizeMeters, furniture.type, furniture.yaw,
        } or { 0, 0, 0, 0 })
    end
    Fuc.safeSend(shader, "u_pointLightCount", math.min(#(world.pointLights or {}), self.maxPointLights))
    for index = 1, self.maxPointLights do
        local light, suffix = world.pointLights and world.pointLights[index], tostring(index - 1)
        if light then
            local pulse = 1
            if (light.pulseAmount or 0) ~= 0 and (light.pulseSpeed or 0) ~= 0 then
                pulse = 1 + math.sin(world.time * light.pulseSpeed + light.phase) * light.pulseAmount
            end
            Fuc.safeSend(shader, "u_pointLightPos" .. suffix, { light.x * world.tileSizeMeters, light.y * world.tileSizeMeters, light.height })
            Fuc.safeSend(shader, "u_pointLightColor" .. suffix, light.color)
            Fuc.safeSend(shader, "u_pointLightParams" .. suffix, { math.max(0, light.intensity * pulse), math.max(0.1, light.radius) })
        else
            Fuc.safeSend(shader, "u_pointLightPos" .. suffix, { 0, 0, 0 })
            Fuc.safeSend(shader, "u_pointLightColor" .. suffix, { 0, 0, 0 })
            Fuc.safeSend(shader, "u_pointLightParams" .. suffix, { 0, 0.1 })
        end
    end
end

function ApartmentRenderer:draw(world)
    if not world.shader or not world.resolveShader or not world.antiAliasShader
        or not world.canvas or not world.mapTexture or not world.presentCanvas then return end

    CalendarTexture.update(world.calendarCanvas, world.sceneState.clock)
    local canvasWidth, canvasHeight = world.canvas:getDimensions()
    local outputWidth, outputHeight = world.historyA:getDimensions()
    local renderPlayer = world.renderPlayer
    renderPlayer.x = Timestep:interpolate(world.previousPlayerPose.x, world.player.x)
    renderPlayer.y = Timestep:interpolate(world.previousPlayerPose.y, world.player.y)
    renderPlayer.height = Timestep:interpolate(world.previousPlayerPose.height, world.player.height)
    renderPlayer.dir, renderPlayer.pitch, renderPlayer.fov = world.player.dir, world.player.pitch, world.player.fov
    local camera = cameraState(renderPlayer, world.tileSizeMeters, canvasWidth, canvasHeight)
    local positionDelta = cameraMotion(world.player, world.previousPlayerPose, world.tileSizeMeters)
    local _, directionDelta = cameraMotion(renderPlayer, world.previousCamera, world.tileSizeMeters)
    local historyWeight = self:historyWeight(positionDelta, directionDelta, world.historyReady)
    local allowTemporal = world.temporalUpscaleEnabled and historyWeight > 0
    local jitter = allowTemporal and JITTER_SEQUENCE[(world.frameIndex % #JITTER_SEQUENCE) + 1] or { 0, 0 }

    love.graphics.push("all")
    GpuProfiler:beginFrame()
    GpuProfiler:beginPass("raymarch", "apt_canvas")
    love.graphics.setCanvas(world.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(world.shader)
    self:uploadScene(world, world.shader, camera, renderPlayer, jitter, canvasWidth, canvasHeight)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, canvasWidth, canvasHeight)
    GpuProfiler:endPass()

    local historySource, historyTarget = world.historyA, world.historyB
    if world.frameIndex % 2 ~= 0 then historySource, historyTarget = historyTarget, historySource end
    if world.temporalUpscaleEnabled then
        GpuProfiler:beginPass("taau", "history")
        love.graphics.setShader()
        love.graphics.setCanvas(historyTarget)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setShader(world.resolveShader)
        local historyOffset = { (world.previousJitter[1] - jitter[1]) / canvasWidth, (world.previousJitter[2] - jitter[2]) / canvasHeight }
        Fuc.safeSend(world.resolveShader, "u_lowResTex", world.canvas)
        Fuc.safeSend(world.resolveShader, "u_historyTex", historySource)
        Fuc.safeSend(world.resolveShader, "u_lowResSize", { canvasWidth, canvasHeight })
        Fuc.safeSend(world.resolveShader, "u_outputSize", { outputWidth, outputHeight })
        Fuc.safeSend(world.resolveShader, "u_historyWeight", historyWeight)
        Fuc.safeSend(world.resolveShader, "u_sharpness", self.sharpness)
        Fuc.safeSend(world.resolveShader, "u_historyReady", allowTemporal and 1 or 0)
        Fuc.safeSend(world.resolveShader, "u_historyUvOffset", historyOffset)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, outputWidth, outputHeight)
        GpuProfiler:endPass()
    end

    GpuProfiler:beginPass("present", "apt_present")
    love.graphics.setCanvas(world.presentCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    if world.temporalUpscaleEnabled then love.graphics.draw(historyTarget, 0, 0)
    else love.graphics.draw(world.canvas, 0, 0, 0, outputWidth / canvasWidth, outputHeight / canvasHeight) end
    GpuProfiler:endPass()

    local screenWidth, screenHeight = love.graphics.getDimensions()
    local scale = math.min(screenWidth / outputWidth, screenHeight / outputHeight)
    local drawX, drawY = (screenWidth - outputWidth * scale) * 0.5, (screenHeight - outputHeight * scale) * 0.5
    GpuProfiler:beginPass("fxaa", "screen")
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)
    Fuc.safeSend(world.antiAliasShader, "u_texelSize", { 1 / outputWidth, 1 / outputHeight })
    Fuc.safeSend(world.antiAliasShader, "u_fxaaEnabled", world.antiAliasEnabled and 1 or 0)
    Fuc.safeSend(world.antiAliasShader, "u_drowsiness", world.sceneState.rest.drowsiness or 0)
    love.graphics.setShader(world.antiAliasShader)
    love.graphics.draw(world.presentCanvas, drawX, drawY, 0, scale, scale)
    GpuProfiler:endPass()
    love.graphics.setShader()
    love.graphics.pop()

    world.historyReady, world.previousCamera = world.temporalUpscaleEnabled, camera
    world.previousJitter = { jitter[1], jitter[2] }
    world.frameIndex = world.frameIndex + 1
end

function ApartmentRenderer:drawSnapshot(world)
    if not world.presentCanvas or not world.historyA then return end
    local outputWidth, outputHeight = world.historyA:getDimensions()
    local screenWidth, screenHeight = love.graphics.getDimensions()
    local scale = math.min(screenWidth / outputWidth, screenHeight / outputHeight)
    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    if world.antiAliasShader then
        Fuc.safeSend(world.antiAliasShader, "u_texelSize", { 1 / outputWidth, 1 / outputHeight })
        Fuc.safeSend(world.antiAliasShader, "u_fxaaEnabled", world.antiAliasEnabled and 1 or 0)
        Fuc.safeSend(world.antiAliasShader, "u_drowsiness", world.sceneState.rest.drowsiness or 0)
        love.graphics.setShader(world.antiAliasShader)
    end
    love.graphics.draw(world.presentCanvas, (screenWidth - outputWidth * scale) * 0.5,
        (screenHeight - outputHeight * scale) * 0.5, 0, scale, scale)
    love.graphics.pop()
end

function ApartmentRenderer:resize(world, width, height)
    if not world.historyA then return end
    world.historyA = ResourceManager:resetCanvas("apt_history_a", width, height)
    world.historyB = ResourceManager:resetCanvas("apt_history_b", width, height)
    world.presentCanvas = ResourceManager:resetCanvas("apt_present", width, height)
    for _, canvas in ipairs({ world.historyA, world.historyB, world.presentCanvas }) do canvas:setFilter("linear", "linear") end
    self:resetHistory(world)
end

return ApartmentRenderer
