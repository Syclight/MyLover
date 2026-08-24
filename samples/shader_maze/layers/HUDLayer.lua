local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")

local HUDLayer = BaseLayer:extend()

local MINIMAP_RADIUS = 6
local MINIMAP_CELL_SIZE = 14
local BIGMAP_PADDING = 48
local BIGMAP_MAX_CELL_SIZE = 18
local MINIMAP_SMOOTH_SPEED = 10

local function drawInteractionUI(uiState, uiFont, detailFont)
    if not uiState then
        return
    end

    local w, h = love.graphics.getDimensions()
    local centerX = w * 0.5
    local centerY = h * 0.5

    if uiState.showDetail and uiState.detailInteractable then
        love.graphics.setColor(0, 0, 0, 0.86)
        love.graphics.rectangle("fill", 0, 0, w, h)

        if detailFont then
            love.graphics.setFont(detailFont)
        end
        love.graphics.setColor(1, 0.96, 0.88, 1)
        love.graphics.printf(uiState.detailInteractable.desc or "调查", w * 0.5 - 260, h * 0.5 - 180, 520, "center")

        if uiFont then
            love.graphics.setFont(uiFont)
        end
        love.graphics.setColor(0.95, 0.92, 0.86, 0.96)
        love.graphics.printf(uiState.detailInteractable.detail or "", w * 0.5 - 280, h * 0.5 - 110, 560, "center")
        love.graphics.setColor(0.74, 0.72, 0.68, 0.95)
        love.graphics.printf("左键 / E 关闭", w * 0.5 - 100, h - 56, 200, "center")
        return
    end

    love.graphics.setColor(1, 1, 1, 0.72)
    love.graphics.circle("line", centerX, centerY, 6)
    love.graphics.line(centerX - 10, centerY, centerX - 3, centerY)
    love.graphics.line(centerX + 3, centerY, centerX + 10, centerY)
    love.graphics.line(centerX, centerY - 10, centerX, centerY - 3)
    love.graphics.line(centerX, centerY + 3, centerX, centerY + 10)

    if uiState.hoveredInteractable then
        local promptWidth = 300
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", centerX - promptWidth * 0.5, h - 124, promptWidth, 38, 6)
        if uiFont then
            love.graphics.setFont(uiFont)
        end
        love.graphics.setColor(1, 0.96, 0.88, 0.98)
        love.graphics.printf(
            string.format("[调查] %s  左键 / E", uiState.hoveredInteractable.desc or uiState.hoveredInteractable.type or "物体"),
            centerX - promptWidth * 0.5,
            h - 113,
            promptWidth,
            "center"
        )
    end
end

local function drawPlayerMarker(x, y, dir, lineLength, radius)
    love.graphics.setColor(0.92, 0.82, 0.34, 1)
    love.graphics.circle("fill", x, y, radius)
    love.graphics.setColor(1, 0.95, 0.55, 0.85)
    love.graphics.line(x, y, x + math.cos(dir) * lineLength, y + math.sin(dir) * lineLength)
end

local function drawRegionalMinimap(minimapImage, minimapData, player, centerX, centerY)
    if not minimapImage or not minimapData or not player then
        return
    end

    local scale = MINIMAP_CELL_SIZE
    local padding = 18
    local diameter = MINIMAP_RADIUS * 2 + 1
    local width = diameter * scale
    local height = diameter * scale

    love.graphics.setColor(0.04, 0.04, 0.04, 0.72)
    love.graphics.rectangle("fill", padding - 6, padding - 6, width + 12, height + 12, 6)

    love.graphics.setScissor(padding - 6, padding - 6, width + 12, height + 12)
    love.graphics.setColor(1, 1, 1, 0.92)
    love.graphics.draw(
        minimapImage,
        padding + (-centerX + MINIMAP_RADIUS) * scale,
        padding + (-centerY + MINIMAP_RADIUS) * scale,
        0,
        scale,
        scale
    )
    love.graphics.setScissor()

    local px = padding + (player.x - centerX + MINIMAP_RADIUS) * scale
    local py = padding + (player.y - centerY + MINIMAP_RADIUS) * scale
    drawPlayerMarker(px, py, player.dir, 14, 3.5)
end

local function drawBigMap(minimapImage, minimapData, player)
    if not minimapImage or not minimapData or not player then
        return
    end

    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    local availableWidth = math.max(120, screenWidth - BIGMAP_PADDING * 2)
    local availableHeight = math.max(120, screenHeight - BIGMAP_PADDING * 2 - 70)
    local scale = math.min(
        BIGMAP_MAX_CELL_SIZE,
        availableWidth / minimapData.width,
        availableHeight / minimapData.height
    )
    local mapWidth = minimapData.width * scale
    local mapHeight = minimapData.height * scale
    local originX = (screenWidth - mapWidth) * 0.5
    local originY = (screenHeight - mapHeight) * 0.5 - 12

    love.graphics.setColor(0.02, 0.02, 0.02, 0.82)
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)
    love.graphics.setColor(0.08, 0.08, 0.08, 0.92)
    love.graphics.rectangle("fill", originX - 10, originY - 10, mapWidth + 20, mapHeight + 20, 10)

    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.draw(minimapImage, originX, originY, 0, scale, scale)

    local px = originX + player.x * scale
    local py = originY + player.y * scale
    drawPlayerMarker(px, py, player.dir, math.max(12, scale * 1.8), math.max(4, scale * 0.28))

    love.graphics.setColor(0.95, 0.92, 0.86, 0.94)
    love.graphics.print("M 大地图  Tab 区域小地图", originX, originY + mapHeight + 18)
end

function HUDLayer:new(sceneState)
    local instance = BaseLayer.new(self)
    instance.sceneState = sceneState
    instance.minimapCenterX = nil
    instance.minimapCenterY = nil
    instance.minimapImage = nil
    return instance
end

function HUDLayer:enter()
    self.font = ResourceManager:get("font_NotoSerifSC-Regular_14")
    self.titleFont = ResourceManager:get("font_NotoSerifSC-Regular_18")
    self.detailFont = ResourceManager:get("font_NotoSerifSC-Regular_24")
end

function HUDLayer:update(dt)
    if not self.sceneState or not self.sceneState.minimap or not self.sceneState.minimap.player then
        return
    end

    self.minimapImage = self.sceneState.minimap.map and self.sceneState.minimap.map.image or nil

    local player = self.sceneState.minimap.player
    if self.minimapCenterX == nil or self.minimapCenterY == nil then
        self.minimapCenterX = player.x
        self.minimapCenterY = player.y
        return
    end

    local t = math.min(1.0, dt * MINIMAP_SMOOTH_SPEED)
    self.minimapCenterX = self.minimapCenterX + (player.x - self.minimapCenterX) * t
    self.minimapCenterY = self.minimapCenterY + (player.y - self.minimapCenterY) * t
end

function HUDLayer:draw()
    if not self.sceneState then
        return
    end

    love.graphics.push("all")

    if self.titleFont then
        love.graphics.setFont(self.titleFont)
    end
    love.graphics.setColor(0.97, 0.93, 0.84, 1)
    love.graphics.print("Shader Maze", 18, love.graphics.getHeight() - 104)

    if self.font then
        love.graphics.setFont(self.font)
    end
    love.graphics.setColor(0.95, 0.92, 0.86, 0.92)
    love.graphics.print("W/S 前后  鼠标转向  A/D 平移  Tab 区域小地图", 18, love.graphics.getHeight() - 78)
    love.graphics.print("左键/E 调查  U 超分  I 抗锯齿  M 大地图  P 返回旧 Raycast", 18, love.graphics.getHeight() - 56)

    local worldConfig = self.sceneState.worldConfig or {}
    local tileSize = tonumber(worldConfig.tileSizeMeters) or 0.5
    local scaleText = string.format("比例: 1 格 = %.1f 米", tileSize)
    local uiState = self.sceneState.ui or {}
    local srText = uiState.superResolutionEnabled and "超分: 开" or "超分: 关"
    local aaText = uiState.antiAliasEnabled and "抗锯齿: 开" or "抗锯齿: 关"
    love.graphics.print(scaleText, 18, love.graphics.getHeight() - 22)
    love.graphics.print(srText, 220, love.graphics.getHeight() - 22)
    love.graphics.print(aaText, 330, love.graphics.getHeight() - 22)

    local minimap = self.sceneState.minimap
    if minimap and minimap.visible ~= false then
        drawRegionalMinimap(
            self.minimapImage,
            minimap.map,
            minimap.player,
            self.minimapCenterX or minimap.player.x,
            self.minimapCenterY or minimap.player.y
        )
    end

    if minimap and minimap.bigVisible then
        drawBigMap(self.minimapImage, minimap.map, minimap.player)
    end

    drawInteractionUI(self.sceneState.ui, self.font, self.detailFont)

    love.graphics.pop()
end

function HUDLayer:exit()
    self.minimapImage = nil
end

return HUDLayer
