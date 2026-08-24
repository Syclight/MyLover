local BaseLayer = require("engine.layers.BaseLayer")
local ResourceManager = require("engine.managers.ResourceManager")

local HUDLayer = BaseLayer:extend()

function HUDLayer:new(sceneState)
    local instance = BaseLayer.new(self)
    instance.sceneState = sceneState
    instance.isHUDLayer = true
    return instance
end

function HUDLayer:enter()
    self.defaultFont = ResourceManager:get("font_default_12")
    self.uiFont = ResourceManager:get("font_NotoSerifSC-Regular_14")
    self.detailFont = ResourceManager:get("font_NotoSerifSC-Regular_24")
end

local function drawMinimap(map, player)
    if not map or not map[1] or not player then
        return
    end

    local mapScale = 8
    local offsetX = 15
    local offsetY = 15

    local mapWidth = #map[1] * mapScale
    local mapHeight = #map * mapScale
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", offsetX - 5, offsetY - 5, mapWidth + 10, mapHeight + 10, 5)

    for y = 1, #map do
        for x = 1, #map[y] do
            local drawX = offsetX + (x - 1) * mapScale
            local drawY = offsetY + (y - 1) * mapScale
            local cell = map[y][x]

            if cell and cell.visible then
                if cell.color then
                    love.graphics.setColor(cell.color[1], cell.color[2], cell.color[3], 0.8)
                else
                    love.graphics.setColor(1, 1, 1, 0.8)
                end
                love.graphics.rectangle("fill", drawX, drawY, mapScale, mapScale)
            end

            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.rectangle("line", drawX, drawY, mapScale, mapScale)
        end
    end

    local px = offsetX + player.x * mapScale
    local py = offsetY + player.y * mapScale

    love.graphics.setColor(0, 1, 0)
    love.graphics.circle("fill", px, py, 4)

    local lineLen = 20
    love.graphics.setColor(1, 1, 0, 0.8)
    love.graphics.line(px, py, px + math.cos(player.dir) * lineLen, py + math.sin(player.dir) * lineLen)

    love.graphics.setColor(1, 1, 0, 0.3)
    local leftAngle = player.dir - player.fov / 2
    local rightAngle = player.dir + player.fov / 2
    love.graphics.line(px, py, px + math.cos(leftAngle) * lineLen, py + math.sin(leftAngle) * lineLen)
    love.graphics.line(px, py, px + math.cos(rightAngle) * lineLen, py + math.sin(rightAngle) * lineLen)
end

local function drawInteractionUI(uiState, uiFont, detailFont)
    if not uiState then
        return
    end

    local w, h = love.graphics.getDimensions()
    local cursor = uiState.cursor or { x = 0, y = 0 }
    local mx = cursor.x or 0
    local my = cursor.y or 0

    if uiState.showDetail and uiState.detailSprite then
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle("fill", 0, 0, w, h)

        love.graphics.setFont(detailFont)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(uiState.detailSprite.detail, w / 2 - 250, h / 2 - 200, 500, "center")

        love.graphics.setFont(uiFont)
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        love.graphics.printf("— 点击任意处关闭 —", w / 2 - 100, h - 50, 200, "center")
    elseif uiState.hoveredSprite then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", mx + 15, my + 15, 180, 30, 4)

        love.graphics.setFont(uiFont)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("[调查] " .. uiState.hoveredSprite.desc, mx + 25, my + 18)

        love.graphics.setColor(1, 0.8, 0.2, 0.8)
        love.graphics.circle("line", mx, my, 6)
    else
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("line", mx, my, 3)
    end
end

function HUDLayer:draw()
    if not self.sceneState then
        return
    end

    love.graphics.push("all")

    local minimapState = self.sceneState.minimap
    if minimapState and minimapState.visible ~= false then
        local map = minimapState.map
        local player = minimapState.player
        if map and player then
            drawMinimap(map, player)
        end
    end

    drawInteractionUI(self.sceneState.ui, self.uiFont, self.detailFont)

    if self.defaultFont then
        love.graphics.setFont(self.defaultFont)
    end
    love.graphics.pop()
end

return HUDLayer
