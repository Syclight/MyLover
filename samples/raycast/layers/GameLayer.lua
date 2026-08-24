local ResourceManager = require("engine.managers.ResourceManager")
local BaseLayer = require("engine.layers.BaseLayer")
local RenderPipeline = require("engine.rendering.RenderPipeline")
local GpuProfiler = require("engine.utils.GpuProfiler")
local LevelParser = require("samples.raycast.utils.LevelParser")
local AudioManager = require("engine.managers.AudioManager")

local GameLayer = BaseLayer:extend()

function GameLayer:new(sceneState)
    local instance = BaseLayer.new(self)
    instance.sceneState = sceneState
    return instance
end

-- 1. 定义 2D 地图 (0:空地, 1:红墙, 2:绿墙, 3:蓝墙, 4:半高木箱)
-- 现在的地图被扩大了，走廊和房间更宽敞，模拟1格=1米的世界

-- 声明为空，将在 enter() 中由 JSON 赋值
local map = {}
local player = {}
local tilesets = {}

-- 声明高度变量，供 Shader 使用
local Z_STATUE, MAX_MAP_HEIGHT

-- === 真实世界尺寸设定 ===
local GRID_SIZE = 1      -- 1格 = 1米 (水平宽度)
local PLAYER_HEIGHT = 1.2  -- 玩家眼睛高度 1.2米
local WALL_HEIGHT = 2.3    -- 墙壁总高度 2.3米
local BOX_HEIGHT = 1.0     -- 木箱总高度 1.0米

-- 换算成引擎内部单位 (引擎里 1 单位 = 1 格子的宽)
local UNIT_PER_METER = 1 / GRID_SIZE
local Z_PLAYER = PLAYER_HEIGHT * UNIT_PER_METER -- 玩家视高对应的内部单位 (3.4)

-- === G-Buffer / 管线变量 ===
-- 注意：canvas 不再持有引用——RenderPipeline 按名解析（gAlbedo/gNormal/gDepth/
-- gFinalComposite/raycast_fxaa_canvas），resize 重建后自动拿到新对象。
local gBufferShader
local deferredLightingShader
local fxaaShader
local pipeline
-- pass 绘制体前置声明（enter 里组装管线时按值引用）
local drawGBufferPass, drawLightingPass

-- 设定最大视野距离，用于将深度归一化到 0~1 之间
local MAX_DEPTH = 30.0


-- === 德·基里科风格天空调色板 ===
local skyPalettes = {
    -- 清晨：苍白的黄绿色过渡到微冷的青灰，透着一种未苏醒的冷清
    morning =   { top = {0.2, 0.35, 0.4}, bottom = {0.85, 0.85, 0.65} },
    -- 上午：经典的蔚蓝，但比现实更饱和、更生硬
    noon =      { top = {0.1, 0.3, 0.6}, bottom = {0.6, 0.75, 0.85} },
    -- 下午：标志性的形而上学风格。天顶是沉重的孔雀绿/暗蓝，地平线是刺目的焦土黄
    afternoon = { top = {0.05, 0.2, 0.25}, bottom = {0.9, 0.7, 0.2} },
    -- 傍晚：幽暗的紫罗兰色压迫着地平线最后一抹砖红/铁锈色
    evening =   { top = {0.15, 0.1, 0.25}, bottom = {0.6, 0.3, 0.15} },
    -- 夜晚：近乎纯黑的深靛蓝，底部透着一丝诡异的幽绿光芒
    night =     { top = {0.02, 0.02, 0.08}, bottom = {0.1, 0.15, 0.1} }
}

local skyPalettesKeys = {"morning", "noon", "afternoon", "evening", "night"}

-- 当前的时间状态
local currentTime = skyPalettesKeys[3] -- 默认是 "afternoon"
-- local currentTime = 2

-- ==========================================
-- 【新增】各时段的太阳方向向量
-- ==========================================
local sunDirections = {
    -- X/Y 决定影子的东南西北朝向，Z 决定太阳高度 (Z越小，影子越长)
    morning   = { 0.8,  0.5, 0.15 }, -- 太阳在东边低空，拉出极长的斜影
    noon      = { 0.1,  0.1, 0.90 }, -- 太阳几乎在顶空直射，影子极短
    afternoon = {-0.6, -0.3, 0.40 }, -- 太阳移动到西偏南，影子向东北拉长
    evening   = {-0.9, -0.6, 0.10 }, -- 太阳在西边极低空，影子长到夸张
    night     = { 0.0,  0.2, 0.80 }  -- 月光，角度偏高且微弱
}

-- 【新增】用于平滑插值的当前状态
local currentSunDir = {0.8, -0.2, 0.25}
local currentSkyColors = {
    top = {0,0,0}, bottom = {0,0,0}
}
local autoTimeTimer = 0 -- 用于自动流逝时间

local skyMesh = nil

-- 【新增】贴图相关的变量
local texture
local textureWidth = 64
local textureHeight = 64
local wallQuads = {}

local statueTex  -- 雕像贴图，需传给阴影着色器

local skyTexture
local skyWidth = 512
local skyHeight = 256

local floorTexture
local floorWidth = 64
local floorHeight = 64
local singlePixelQuad -- 用于地板绘制的 1x1 Quad

-- local lastLKeyPressed = false
local lastTKeyDown = false
local zBuffer = {}

local boxTexture
local boxQuads = {}

local gMapTex

-- 精灵与鼠标交互状态
local sprites = {}
local mouseState = {
    hoveredSprite = nil,  -- 当前悬停的精灵
    showDetail = false,   -- 是否显示详情
    detailSprite = nil    -- 当前展示详情的精灵
}
local lastMouseDown = false
local gBufferSpriteShader
local gBufferPaintingShader

-- 画作相关的变量
local paintingTextures = {}

-- 画框相关变量
local frameAlbedoTex
local frameNormalTex

-- 悬停缓存
local hoveredPaintingThisFrame = nil
local DEFAULT_PAINTING_TEXTURE = "painting"

local function findTileHeight(tileName, fallbackHeight)
    for _, tile in pairs(tilesets) do
        if tile.name == tileName then
            return tile.height * UNIT_PER_METER
        end
    end

    return fallbackHeight * UNIT_PER_METER
end

local function getPaintingFrameConfig(tile)
    local defaults = {
        scale = 1.0,
        width = 0.9,
        height = 0.9,
        zOffset = 1.4,
        frameThickness = 0.08,
        depthBias = 0.03
    }

    if not tile or not tile.paintingFrame then
        return defaults
    end

    return tile.paintingFrame
end

local function scaleColor(color, factor)
    return {
        math.min(1, color[1] * factor),
        math.min(1, color[2] * factor),
        math.min(1, color[3] * factor)
    }
end

-- 生成画作贴图
local function createPaintingTexture(image)
    image:setFilter("nearest", "nearest") -- 保持像素复古感
    
    local width = image:getWidth()
    local height = image:getHeight()
    
    local quads = {}
    for i = 0, width - 1 do
        -- 同样切成垂直切片
        quads[i] = love.graphics.newQuad(i, 0, 1, height, width, height)
    end
    
    return image, quads, width, height
end

local function buildPaintingTexturePath(textureName)
    return "samples/raycast/assets/images/" .. textureName .. ".png"
end

local function loadPaintingTexture(textureName)
    local resolvedName = textureName or DEFAULT_PAINTING_TEXTURE
    if paintingTextures[resolvedName] then
        return paintingTextures[resolvedName]
    end

    local image = ResourceManager:getScopeScene(resolvedName)
    if not image then
        local imagePath = buildPaintingTexturePath(resolvedName)
        if love.filesystem.getInfo(imagePath) then
            ResourceManager:loadImage(imagePath, "scene", resolvedName, true)
            image = ResourceManager:getScopeScene(resolvedName)
        end
    end

    if not image and resolvedName ~= DEFAULT_PAINTING_TEXTURE then
        return loadPaintingTexture(DEFAULT_PAINTING_TEXTURE)
    end

    if not image then
        error("Raycast GameLayer: missing painting texture '" .. resolvedName .. "'.")
    end

    local _, quads, width, height = createPaintingTexture(image)
    local asset = {
        name = resolvedName,
        image = image,
        quads = quads,
        width = width,
        height = height
    }
    paintingTextures[resolvedName] = asset
    return asset
end

local function preloadPaintingTextures(parsedLevel)
    local requiredTextures = {
        [DEFAULT_PAINTING_TEXTURE] = true
    }

    for _, tile in pairs(parsedLevel.tilesets or {}) do
        if tile.renderType == "painting_wall" then
            requiredTextures[tile.texture or DEFAULT_PAINTING_TEXTURE] = true
        end
    end

    for textureName in pairs(requiredTextures) do
        loadPaintingTexture(textureName)
    end
end

local function drawWallTopTrim(x, drawStart, resolution, screenHeight, correctedDist, baseUnitHeight, zHeight, tileColor)
    if zHeight < 1.8 or screenHeight <= 0 then
        return
    end

    local primaryTrimHeight = math.max(1, math.min(baseUnitHeight * 0.06, screenHeight * 0.09))
    local secondaryTrimHeight = math.max(1, math.min(baseUnitHeight * 0.035, screenHeight * 0.05))
    local trimGapHeight = math.max(1, math.min(baseUnitHeight * 0.008, screenHeight * 0.012))
    local primaryLipHeight = math.max(1, math.min(baseUnitHeight * 0.012, screenHeight * 0.018))
    local secondaryLipHeight = math.max(1, math.min(baseUnitHeight * 0.009, screenHeight * 0.014))
    local trimShadowHeight = math.max(1, math.min(baseUnitHeight * 0.01, screenHeight * 0.014))

    local primaryTrimDepth = math.max(0.01, correctedDist - 0.065)
    local primaryLipDepth = math.max(0.01, correctedDist - 0.046)
    local secondaryTrimDepth = math.max(0.01, correctedDist - 0.038)
    local secondaryLipDepth = math.max(0.01, correctedDist - 0.026)

    local primaryTrimColor = scaleColor(tileColor, 1.2)
    local secondaryTrimColor = scaleColor(tileColor, 1.1)
    local primaryLipColor = scaleColor(tileColor, 0.72)
    local secondaryLipColor = scaleColor(tileColor, 0.78)
    local trimShadowColor = scaleColor(tileColor, 0.64)

    gBufferShader:send("u_depth", primaryTrimDepth)
    love.graphics.setColor(primaryTrimColor[1], primaryTrimColor[2], primaryTrimColor[3], 1)
    love.graphics.rectangle("fill", x, drawStart, resolution, primaryTrimHeight)

    gBufferShader:send("u_depth", primaryLipDepth)
    love.graphics.setColor(primaryLipColor[1], primaryLipColor[2], primaryLipColor[3], 1)
    love.graphics.rectangle("fill", x, drawStart + primaryTrimHeight, resolution, primaryLipHeight)

    gBufferShader:send("u_depth", correctedDist)
    love.graphics.setColor(trimShadowColor[1], trimShadowColor[2], trimShadowColor[3], 0.95)
    love.graphics.rectangle("fill", x, drawStart + primaryTrimHeight + primaryLipHeight, resolution, trimGapHeight)

    gBufferShader:send("u_depth", secondaryTrimDepth)
    love.graphics.setColor(secondaryTrimColor[1], secondaryTrimColor[2], secondaryTrimColor[3], 1)
    love.graphics.rectangle(
        "fill",
        x,
        drawStart + primaryTrimHeight + primaryLipHeight + trimGapHeight,
        resolution,
        secondaryTrimHeight
    )

    gBufferShader:send("u_depth", secondaryLipDepth)
    love.graphics.setColor(secondaryLipColor[1], secondaryLipColor[2], secondaryLipColor[3], 1)
    love.graphics.rectangle(
        "fill",
        x,
        drawStart + primaryTrimHeight + primaryLipHeight + trimGapHeight + secondaryTrimHeight,
        resolution,
        secondaryLipHeight
    )

    gBufferShader:send("u_depth", correctedDist)
    love.graphics.setColor(trimShadowColor[1], trimShadowColor[2], trimShadowColor[3], 0.95)
    love.graphics.rectangle(
        "fill",
        x,
        drawStart + primaryTrimHeight + primaryLipHeight + trimGapHeight + secondaryTrimHeight + secondaryLipHeight,
        resolution,
        trimShadowHeight
    )
end

-- 生成一个的古典石膏像
local function createStatueTexture()
    -- local imagePath = "assets/images/statue.png"
    -- local imagePath = ResourceManager:get("statue")
    
    -- 1. 加载用于 GPU 渲染的贴图
    -- local image = love.graphics.newImage(imagePath)
    local image = ResourceManager:getScopeScene("statue")
    -- 可选：如果你想要保持复古的像素硬边缘，保留下面这行；如果要平滑过渡，可以删掉
    image:setFilter("nearest", "nearest")
    
    -- 2. 加载用于 CPU 像素级碰撞检测的数据
    -- local imageData = love.image.newImageData(imagePath)
    local imageData = ResourceManager:getScopeScene("statue_data")
    
    -- 3. 动态获取这张图片的真实宽高
    local width = image:getWidth()
    local height = image:getHeight()
    
    -- 4. 自动生成垂直切片 Quads
    local quads = {}
    for i = 0, width - 1 do
        quads[i] = love.graphics.newQuad(i, 0, 1, height, width, height)
    end
    
    -- 把宽高也一起返回去，做到完全动态适配
    return image, quads, imageData, width, height
end

local function updateSkyMesh()
    local w, h = love.graphics.getDimensions()
    
    -- 直接读取我们正在平滑插值中的当前颜色
    local vertices = {
        {0, 0, 0, 0, currentSkyColors.top[1], currentSkyColors.top[2], currentSkyColors.top[3], 1},
        {w, 0, 0, 0, currentSkyColors.top[1], currentSkyColors.top[2], currentSkyColors.top[3], 1},
        {w, h / 2, 0, 0, currentSkyColors.bottom[1], currentSkyColors.bottom[2], currentSkyColors.bottom[3], 1},
        {0, h / 2, 0, 0, currentSkyColors.bottom[1], currentSkyColors.bottom[2], currentSkyColors.bottom[3], 1},
    }

    if skyMesh then
        skyMesh:setVertices(vertices)
    else
        skyMesh = love.graphics.newMesh(4, "fan", "dynamic")
        skyMesh:setVertices(vertices)
    end
end

local function ensureSceneUIState(sceneState)
    if not sceneState then
        return {
            hoveredSprite = nil,
            showDetail = false,
            detailSprite = nil,
            cursor = { x = 0, y = 0 }
        }
    end

    sceneState.ui = sceneState.ui or {}
    sceneState.ui.cursor = sceneState.ui.cursor or { x = 0, y = 0 }
    return sceneState.ui
end

local function syncSceneState(sceneState)
    if not sceneState then
        return
    end

    sceneState.minimap = sceneState.minimap or {}
    sceneState.minimap.map = map
    sceneState.minimap.player = player
    sceneState.minimap.visible = not mouseState.showDetail
    sceneState.ui = mouseState
end

function GameLayer:enter()
    print("Entered Metaphysical Deferred Rendering Mode!")
   
    -- 清理遗留状态
    sprites = {}
    mouseState = ensureSceneUIState(self.sceneState)
    mouseState.hoveredSprite = nil
    mouseState.showDetail = false
    mouseState.detailSprite = nil
    mouseState.cursor.x = 0
    mouseState.cursor.y = 0
    love.mouse.setVisible(false)
    love.keyboard.setTextInput(false)

    -- 1. 一键加载所有该场景资源！
    ResourceManager:loadManifest("samples/raycast/assets/manifest.lua")

    -- 2. 绑定着色器引用（canvas 由 RenderPipeline 按名解析，不持引用）
    gBufferShader = ResourceManager:getScopeScene("gbuffer_shader")
    deferredLightingShader = ResourceManager:getScopeScene("shadow_shader")
    gBufferSpriteShader = ResourceManager:getScopeScene("sprite_shader")
    gBufferPaintingShader = ResourceManager:getScopeScene("painting_shader")
    fxaaShader = ResourceManager:getScopeScene("raycast_fxaa_shader")
    if fxaaShader:hasUniform("texelSize") then
        local w, h = love.graphics.getDimensions()
        fxaaShader:send("texelSize", { 1.0 / w, 1.0 / h })
    end

    -- 3. 组装渲染管线：GBuffer(MRT) → 延迟光照 → FXAA 捕获 → 合成到 backbuffer。
    -- 每个 pass 出口由管线强制还原状态，HUD 层拿到的永远是干净的 2D 基线。
    pipeline = RenderPipeline.new("raycast")
    pipeline:addPass({
        name = "gbuffer",
        output = { "gAlbedo", "gNormal", "gDepth" },
        clear = { 0, 0, 0, 0 },
        state = { shader = gBufferShader },
        draw = drawGBufferPass,
    })
    pipeline:addPass({
        name = "deferred_light",
        input = { "gAlbedo", "gNormal", "gDepth" },
        output = "gFinalComposite",
        clear = { 0, 0, 0, 1 },
        state = { shader = deferredLightingShader, color = { 1, 1, 1, 1 } },
        draw = drawLightingPass,
    })
    pipeline:addPass({
        name = "fxaa_capture",
        input = "gFinalComposite",
        output = "raycast_fxaa_canvas",
        clear = true,
        draw = function(_, inputs) love.graphics.draw(inputs[1], 0, 0) end,
    })
    pipeline:addPass({
        name = "present",
        input = "raycast_fxaa_canvas",
        state = { shader = fxaaShader, color = { 1, 1, 1, 1 } },
        draw = function(_, inputs) love.graphics.draw(inputs[1], 0, 0) end,
    })


    -- -- 深度图需要更高的精度，如果显卡支持，我们尽量使用 r16f (16位浮点)
    -- local formats = love.graphics.getImageFormats()
    -- local depthFormat = formats["r16f"] and "r16f" or "normal"
    -- gDepth  = love.graphics.newCanvas(w, h, {format = depthFormat})

    -- 解析 JSON 地图数据
    local rawMapData = ResourceManager:getScopeScene("level_1")
    local parsedLevel = LevelParser.parse(rawMapData)

    map = parsedLevel.map
    tilesets = parsedLevel.tilesets
    player = parsedLevel.player
    -- Z_PLAYER = player.height * UNIT_PER_METER
    player.baseHeight = player.height * UNIT_PER_METER
    player.bobPhase = 0
    Z_PLAYER = player.baseHeight
    preloadPaintingTextures(parsedLevel)
    syncSceneState(self.sceneState)

    -- 动态获取给 Shader 用的高度参数
    Z_STATUE = findTileHeight("statue_shadow_blocker", 1.8)
    MAX_MAP_HEIGHT = 0
    for _, tile in pairs(tilesets) do
        MAX_MAP_HEIGHT = math.max(MAX_MAP_HEIGHT, tile.height or 0)
    end


    -- ==================================================
    -- 将 Lua 的语义地图转换为 GPU 可读取的微型贴图
    -- ==================================================
    local mapWidth = #map[1]
    local mapHeight = #map
    local mapImageData = love.image.newImageData(mapWidth, mapHeight)
    
    for y = 1, mapHeight do
        for x = 1, mapWidth do
            local cell = map[y][x]
            local shadowMode = 0
            if cell.shadowMode == "solid" then
                shadowMode = 1
            elseif cell.shadowMode == "alpha" then
                shadowMode = 2
            end

            local encodedShadowMode = shadowMode / 10.0
            local encodedHeight = (MAX_MAP_HEIGHT > 0) and ((cell.height or 0) / MAX_MAP_HEIGHT) or 0
            mapImageData:setPixel(x - 1, y - 1, encodedShadowMode, encodedHeight, 0, 1)
        end
    end
    
    -- 加入 {linear = true} 严禁 LÖVE 对它进行 sRGB 色彩过滤！
    gMapTex = love.graphics.newImage(mapImageData, {linear = true})
    ResourceManager:register("raycast_runtime_map_texture", gMapTex, "scene")
    gMapTex:setFilter("nearest", "nearest")

    -- 2. 编写 G-Buffer 着色器 (GLSL)
    -- 这个 Shader 的作用是：接收 LÖVE 画出的几何体，把它们拆解成 颜色、法线、深度 三份数据输出
    -- gBufferShader = love.graphics.newShader(RaycastGBufferShader)
    
    -- 3. 编写延迟光照着色器 (真实的全局世界空间阴影)
    -- deferredLightingShader = love.graphics.newShader(RaycastGlobalShadow)

    -- 初始化平滑过渡的起始颜色和方向
    local startSky = skyPalettes[currentTime]
    for i=1, 3 do
        currentSkyColors.top[i] = startSky.top[i]
        currentSkyColors.bottom[i] = startSky.bottom[i]
        currentSunDir[i] = sunDirections[currentTime][i]
    end
    updateSkyMesh()

    -- 加载画框资源
    frameAlbedoTex = ResourceManager:getScopeScene("painting_frame_albedo")
    frameNormalTex = ResourceManager:getScopeScene("painting_frame_normal")
    frameNormalTex:setFilter("linear", "linear")

    -- 遍历解析出来的实体列表，动态生成场景对象
    local tex, quads, imgData, texW, texH = createStatueTexture()
    statueTex = tex  -- 保存引用，供阴影着色器使用
    for _, spriteData in ipairs(parsedLevel.sprites) do
        if spriteData.type == "statue_sprite" then
            table.insert(sprites, {
                x = spriteData.x,
                y = spriteData.y,
                texture = tex,
                texWidth = texW,
                texHeight = texH,
                quads = quads,
                imageData = imgData,
                desc = spriteData.properties.desc,
                detail = spriteData.properties.detail
            })
        end
    end

    -- 音频系统
    AudioManager:init()
    AudioManager:playBGM("bgm_ambient", 8.0)
end

function GameLayer:update(dt)
    -- 1. 视角旋转
    -- if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
    --     player.dir = player.dir - 2 * dt
    -- elseif love.keyboard.isDown("right") or love.keyboard.isDown("d") then
    --     player.dir = player.dir + 2 * dt
    -- end

    if not mouseState.showDetail then
        if love.keyboard.isDown("left") or love.keyboard.isScancodeDown("a") then
            player.dir = player.dir - 2 * dt
        elseif love.keyboard.isDown("right") or love.keyboard.isScancodeDown("d") then
            player.dir = player.dir + 2 * dt
        end
    end

    -- 2. 准备移动步长
    -- ==================================================
    -- 【新增】：检测是否按住 Shift 键进行奔跑
    -- ==================================================
    -- local isRunning = love.keyboard.isScancodeDown("lshift")
    local isRunning = false -- 先禁用奔跑功能，等基础功能稳定后再打开它，避免调试时步速过快导致的各种问题
    
    -- 设定基础步速，以及奔跑时的各种状态倍率
    local baseSpeed = 0.8
    local speedMultiplier = isRunning and 1.5 or 1.0  -- 奔跑时速度变成 2.2 倍 (约 4 米/秒)
    local bobMultiplier = isRunning and 1.5 or 1.0    -- 奔跑时视角的起伏幅度变成 1.5 倍
    
    -- 2. 准备最终的移动步长
    local moveSpeed = baseSpeed * speedMultiplier * dt

    local stepX = 0
    local stepY = 0

    if not mouseState.showDetail then
        if love.keyboard.isDown("up") or love.keyboard.isScancodeDown("w") then
            stepX = math.cos(player.dir) * moveSpeed
            stepY = math.sin(player.dir) * moveSpeed
        elseif love.keyboard.isDown("down") or love.keyboard.isScancodeDown("s") then
            stepX = -math.cos(player.dir) * moveSpeed
            stepY = -math.sin(player.dir) * moveSpeed
        end
    end

    -- 【新增】：记录移动前的坐标
    local oldX, oldY = player.x, player.y

    -- 3. 碰撞检测与移动 (X轴与Y轴分离检测)
    if stepX ~= 0 or stepY ~= 0 then
        -- 【修改】由于 1 格代表 50cm，玩家不应该有 0.2 格（10cm）这么小的体积
        -- 把判定半径改为 0.4（即 20cm的半径，40cm的直径），这样靠近墙壁和箱子时的碰撞感更真实
        local padding = 0.4 -- 体积碰撞判定半径

        -- 【检测 X 轴】
        if stepX ~= 0 then
            local nextX = player.x + stepX
            -- 只在移动方向上加 padding
            local checkX = nextX + (stepX > 0 and padding or -padding)
            local mapX = math.floor(checkX) + 1
            local mapY_current = math.floor(player.y) + 1

            -- 【修复了这里的越界判断】只检查 mapY_current 这一行是否存在
            local targetCell = map[mapY_current] and map[mapY_current][mapX]
            if targetCell and not targetCell.blocksMovement then
                player.x = nextX
            end
        end

        -- 【检测 Y 轴】
        if stepY ~= 0 then
            local nextY = player.y + stepY
            local checkY = nextY + (stepY > 0 and padding or -padding)
            local mapX_current = math.floor(player.x) + 1
            local mapY = math.floor(checkY) + 1

            -- 【修复了这里的 Bug】去掉了错误的 map[mapX_current] 判断
            local targetCell = map[mapY] and map[mapY][mapX_current]
            if targetCell and not targetCell.blocksMovement then
                player.y = nextY
            end
        end
    end

    -- ==================================================
    -- 【新增】：计算 View Bobbing (视角上下浮动)
    -- ==================================================
    -- 计算这一帧实际移动的距离
    local distMoved = math.sqrt((player.x - oldX)^2 + (player.y - oldY)^2)

    -- ==================================================
    -- 【新增】：计算视角浮动，并精准触发脚步声
    -- ==================================================
    local oldPhase = player.bobPhase -- 记录上一帧的相位

    -- if distMoved > 0 then
    --     -- 如果在走动，根据走动的距离累加相位 (乘以 bobSpeed 调整步频)
    --     player.bobPhase = player.bobPhase + player.bobSpeed * distMoved
    -- else
    --     -- 如果停下来了，让相位平滑地滑向最近的 math.pi 的整数倍
    --     -- 这样 sin(bobPhase) 就会平滑过渡回 0 (即恢复到原始高度)
    --     local targetPhase = math.floor((player.bobPhase / math.pi) + 0.5) * math.pi
    --     player.bobPhase = player.bobPhase + (targetPhase - player.bobPhase) * 10 * dt
    -- end

    -- -- 计算当前的浮动偏移量，并应用给全场景的 Z_PLAYER
    -- local bobOffset = math.sin(player.bobPhase) * player.bobAmount

    if distMoved > 0 then
        -- 起伏的频率也受到奔跑倍率的影响（虽然跑得快 distMoved 本身就大了，
        -- 但乘以倍率能让步伐频率显得更急促，模拟小碎步或大跨步的切换）
        local currentBobSpeed = player.bobSpeed * (isRunning and 1.0 or 0.8)
        player.bobPhase = player.bobPhase + currentBobSpeed * distMoved
    else
        local targetPhase = math.floor((player.bobPhase / math.pi) + 0.3) * math.pi
        player.bobPhase = player.bobPhase + (targetPhase - player.bobPhase) * 10 * dt
    end

    -- 【修改】：起伏的幅度乘以 bobMultiplier，让奔跑时的重心起伏更剧烈
    -- 使用 -abs(sin) 代替 sin：每一步都向下沉，不会向上浮，
    -- 两个谷值恰好在 phase = 0, π, 2π... 处，与脚步声触发点完全对齐
    local currentBobAmount = player.bobAmount * bobMultiplier
    local bobOffset = -math.abs(math.sin(player.bobPhase)) * currentBobAmount
    Z_PLAYER = player.baseHeight + (bobOffset * UNIT_PER_METER)

    -- 【新增】计算极轻微的左右摇晃视角倾斜 (Roll)
    -- 注意余弦函数的频率是正弦的一半，完美模拟左脚-右脚的重心切换
    -- player.bobRoll = math.cos(player.bobPhase / 2) * 0.01

    -- 【声音触发逻辑】：
    -- 正弦波 sin(x) 在 x = pi/2, 3pi/2 时达到峰值或谷值。
    -- 但我们的步伐周期通常是：踩下(谷值) -> 抬起(峰值)。
    -- 我们把一个完整的 2*pi 周期分为左右脚两步。
    -- 每当 phase 跨过 pi 的整数倍附近时（比如其余数从大于 pi/2 变成接近 pi），代表踩下了一步
    
    local currentStep = math.floor(player.bobPhase / math.pi)
    local previousStep = math.floor(oldPhase / math.pi)

    -- 当当前的步数标记大于上一帧的步数标记，说明刚刚迈出了一步！
    if currentStep > previousStep and distMoved > 0 then
        -- 根据奔跑状态动态调整脚步声的音量和音高波动
        local stepVolume = isRunning and 0.5 or 0.3      -- 跑动时音量加大到 50%
        local stepPitchVariation = isRunning and 0.2 or 0.1 -- 跑动时音高波动更大，显得急促不稳
        local stepVolumeJitter = (love.math.random() * 2 - 1) * 0.04

        AudioManager:play2DSFX("footsteps_concrete", stepPitchVariation, stepVolume + stepVolumeJitter)
    end

    -- ==================================================
    -- 【新增】动态时间流逝与按键切换
    -- ==================================================
    -- 每 20 秒自动流逝到下一个时间段 (你可以改短一点看效果)
    autoTimeTimer = autoTimeTimer + dt
    local switchTime = false

    if autoTimeTimer > 20 then
        autoTimeTimer = 0
        switchTime = true
    end

    if love.keyboard.isScancodeDown("t") and not lastTKeyDown then
        switchTime = true
        autoTimeTimer = 0 -- 手动切换重置计时器
    end

    -- 记录按键状态 (防抖)
    lastTKeyDown = love.keyboard.isScancodeDown("t")

    if switchTime then
        local currentIndex = 1
        for i, key in ipairs(skyPalettesKeys) do
            if key == currentTime then currentIndex = i break end
        end
        local nextIndex = (currentIndex % #skyPalettesKeys) + 1
        currentTime = skyPalettesKeys[nextIndex]
    end

    -- ==================================================
    -- 【核心魔法】光影与天空的平滑插值 (Lerp)
    -- ==================================================
    local targetSun = sunDirections[currentTime]
    local targetSky = skyPalettes[currentTime]
    
    -- 过渡速度：0.5 代表较慢的梦幻渐变，大概需要2-3秒完成平滑过渡
    local transitionSpeed = 0.5 * dt 

    -- 1. 让太阳向量缓慢移动 (改变阴影长度和方向)
    for i = 1, 3 do
        currentSunDir[i] = currentSunDir[i] + (targetSun[i] - currentSunDir[i]) * transitionSpeed
    end

    -- 2. 让天空颜色缓慢晕染
    for i = 1, 3 do
        currentSkyColors.top[i] = currentSkyColors.top[i] + (targetSky.top[i] - currentSkyColors.top[i]) * transitionSpeed
        currentSkyColors.bottom[i] = currentSkyColors.bottom[i] + (targetSky.bottom[i] - currentSkyColors.bottom[i]) * transitionSpeed
    end

    -- 每一帧都根据新的颜色更新天空网格
    updateSkyMesh()

    -- ==================================================
    -- 像素级精确的鼠标悬停与点击调查
    -- ==================================================
    local mx, my = love.mouse.getPosition()
    mouseState.cursor.x = mx
    mouseState.cursor.y = my

    -- 先接收上一帧 draw() 渲染时检测到的画作悬停状态
    mouseState.hoveredSprite = hoveredPaintingThisFrame

    if not mouseState.showDetail then
        for _, sprite in ipairs(sprites) do
            if sprite.drawStartX and sprite.drawEndX then
                -- 1. 粗略的包围盒检测 (AABB)
                if mx >= sprite.drawStartX and mx <= sprite.drawEndX and 
                   my >= sprite.drawStartY and my <= sprite.drawEndY then
                    
                    -- 2. 深度测试 (不能隔着墙透视) 以及 距离限制 (3米以内)
                    if sprite.correctedDist < (zBuffer[math.floor(mx)] or MAX_DEPTH) and sprite.dist < 3.0 then
                        
                        -- ==========================================
                        -- 3. 终极检测：逆向 UV 映射进行 Alpha (透明度) 剔除
                        -- ==========================================
                        local drawWidth = sprite.drawEndX - sprite.drawStartX
                        local drawHeight = sprite.drawEndY - sprite.drawStartY
                        
                        -- 计算鼠标在贴图上的对应坐标 (0 ~ texWidth/texHeight)
                        local texX = math.floor((mx - sprite.drawStartX) / drawWidth * sprite.texWidth)
                        local texY = math.floor((my - sprite.drawStartY) / drawHeight * sprite.texHeight)
                        
                        -- 防止极端情况下的越界
                        texX = math.max(0, math.min(sprite.texWidth - 1, texX))
                        texY = math.max(0, math.min(sprite.texHeight - 1, texY))
                        
                        -- 从我们第一步存下来的 CPU 数据中读取这个像素的颜色
                        local r, g, b, a = sprite.imageData:getPixel(texX, texY)
                        
                        -- 如果该像素不透明 (a > 0)，说明真的指到了雕像本体！
                        if a > 0.1 then
                            mouseState.hoveredSprite = sprite
                        end
                    end
                end
            end
        end
    end

    local mouseDown = love.mouse.isDown(1)
    if mouseDown and not lastMouseDown then
        if mouseState.showDetail then
            mouseState.showDetail = false 
        elseif mouseState.hoveredSprite then
            mouseState.showDetail = true 
            mouseState.detailSprite = mouseState.hoveredSprite
        end
    end
    lastMouseDown = mouseDown

    -- 更新音效管理器，让它根据玩家位置和状态调整环境音效
    AudioManager:update(dt, player)
    syncSceneState(self.sceneState)
end

-- ==================================================
-- gbuffer pass：MRT 写入 gAlbedo/gNormal/gDepth。
-- canvas 绑定/清屏/setShader(gBufferShader) 已由管线在进 pass 时完成。
-- ==================================================
function drawGBufferPass()
    local w, h = love.graphics.getDimensions()

    -- 每一帧画面刷新时重置缓存，并抓取鼠标坐标
    hoveredPaintingThisFrame = nil
    local mx, my = love.mouse.getPosition()

    -- 传入一些全局 Uniform 变量
    gBufferShader:send("u_screenHeight", h)
    gBufferShader:send("u_zPlayer", Z_PLAYER)
    gBufferShader:send("u_maxDepth", MAX_DEPTH)

    -- 1. 画天空 (天空是最远的，法线随便给个朝下的)
    gBufferShader:send("u_isFloor", false)
    gBufferShader:send("u_depth", MAX_DEPTH)
    gBufferShader:send("u_normal", {0, 0, -1})
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(skyMesh, 0, 0)

    -- 2. 画地板 (开启 u_isFloor，Shader 会自动计算逐像素深度)
    gBufferShader:send("u_isFloor", true)
    love.graphics.setColor(0.75, 0.65, 0.5)
    love.graphics.rectangle("fill", 0, h / 2, w, h / 2)

    -- 3. 画墙壁 (关闭 u_isFloor，手动传入深度和法线)
    gBufferShader:send("u_isFloor", false)
    
    -- 初始化 zBuffer (用于后续精灵)
    for i = 0, w do zBuffer[i] = MAX_DEPTH end
    local resolution = 1

    for x = 0, w, resolution do
        local cameraX = 2 * x / w - 1
        local rayAngle = player.dir + (cameraX * player.fov / 2)
        local rayDirX = math.cos(rayAngle)
        local rayDirY = math.sin(rayAngle)
        
        -- ... (此处保留你原本的 DDA 计算逻辑，直接跳到 hits 循环) ...
        local gridX = math.floor(player.x)
        local gridY = math.floor(player.y)
        local deltaDistX = (rayDirX == 0) and math.huge or math.abs(1 / rayDirX)
        local deltaDistY = (rayDirY == 0) and math.huge or math.abs(1 / rayDirY)
        local stepX, stepY
        local sideDistX, sideDistY

        if rayDirX < 0 then stepX = -1; sideDistX = (player.x - gridX) * deltaDistX
        else stepX = 1; sideDistX = (gridX + 1.0 - player.x) * deltaDistX end

        if rayDirY < 0 then stepY = -1; sideDistY = (player.y - gridY) * deltaDistY
        else stepY = 1; sideDistY = (gridY + 1.0 - player.y) * deltaDistY end

        local hitWall = 0
        local side = 0
        local depth = 0
        local hits = {}

        while depth < MAX_DEPTH do
            if sideDistX < sideDistY then
                sideDistX = sideDistX + deltaDistX
                gridX = gridX + stepX; side = 0
            else
                sideDistY = sideDistY + deltaDistY
                gridY = gridY + stepY; side = 1
            end
            depth = depth + 1
            local mapX, mapY = gridX + 1, gridY + 1

            local hitCell = map[mapY] and map[mapY][mapX]
            if hitCell and hitCell.tileId > 0 then
                local perpDist = (side == 0) and ((gridX - player.x + (1 - stepX) / 2) / rayDirX) or ((gridY - player.y + (1 - stepY) / 2) / rayDirY)
                table.insert(hits, { cell = hitCell, type = hitCell.tileId, side = side, dist = perpDist, rx = rayDirX, ry = rayDirY })
                if hitCell.raycastBarrier then break end
            end
        end

        local wallDistForZBuffer = MAX_DEPTH
        for j = #hits, 1, -1 do
            local hit = hits[j]
            local correctedDist = math.max(0.01, hit.dist * math.cos(rayAngle - player.dir))
            local baseUnitHeight = h / correctedDist

            local hitTile = hit.cell
            if hitTile and hitTile.occluder then
                wallDistForZBuffer = correctedDist
            end

            -- ==================================================
            -- 【新增】：计算当前墙面的法线 (Normal)
            -- ==================================================
            local nx, ny, nz = 0, 0, 0
            if hit.side == 0 then
                nx = (hit.rx > 0) and -1 or 1 -- 撞到东西走向的墙
            else
                ny = (hit.ry > 0) and -1 or 1 -- 撞到南北走向的墙
            end
            
            -- 发送给 Shader
            gBufferShader:send("u_normal", {nx, ny, nz})
            gBufferShader:send("u_depth", correctedDist)

            -- 设定 Chirico 风格纯色 (注意：去掉了以前的代码光影计算，把颜色交给本色)
            -- 从 tilesets 动态获取颜色和高度
            local ts = hit.cell
            if ts and ts.visible then
                love.graphics.setColor(ts.color[1], ts.color[2], ts.color[3])
                
                -- 计算动态高度
                local zHeight = ts.height * UNIT_PER_METER
                local drawStart = (h / 2) - baseUnitHeight * (zHeight - Z_PLAYER)
                local screenHeight = ((h / 2) + baseUnitHeight * Z_PLAYER) - drawStart
                
                love.graphics.rectangle("fill", x, drawStart, resolution, screenHeight)
                if ts.kind == "wall" then
                    drawWallTopTrim(x, drawStart, resolution, screenHeight, correctedDist, baseUnitHeight, zHeight, ts.color)
                    love.graphics.setColor(ts.color[1], ts.color[2], ts.color[3], 1)
                end

                -- ==================================================
                -- 【新增】：如果是挂着画的墙，在纯色底漆上额外画出贴图
                -- ==================================================
                local paintingAsset = paintingTextures[ts.texture or DEFAULT_PAINTING_TEXTURE]
                if not paintingAsset and ts.renderType == "painting_wall" then
                    paintingAsset = loadPaintingTexture(ts.texture or DEFAULT_PAINTING_TEXTURE)
                end
                if ts.renderType == "painting_wall" and paintingAsset then
                    
                    -- 1. 解析当前射线到底击中了方块的哪一个面
                    local hitFace = ""
                    if hit.side == 0 then
                        -- 射线沿X轴移动，击中了垂直于X轴的面
                        -- 射线向东(rx>0)代表打在西面；射线向西(rx<0)代表打在东面
                        hitFace = (hit.rx > 0) and "west" or "east"
                    else
                        -- 射线沿Y轴移动，击中了垂直于Y轴的面
                        -- 射线向南(ry>0)代表打在北面；射线向北(ry<0)代表打在南面
                        hitFace = (hit.ry > 0) and "north" or "south"
                    end
                    
                    -- 2. 获取 JSON 中配置的目标面（如果没有配置，默认四面都画）
                    local targetFace = ts.properties.face or "all"
                    
                    -- 3. 只有当当前命中的面与目标面一致时，才进行渲染和交互检测
                    if targetFace == "all" or targetFace == hitFace then
                        
                        -- 计算射线击中这格墙壁的精确局部坐标 (wallX 范围 0.0 ~ 1.0)
                        local wallX
                        if hit.side == 0 then
                            wallX = player.y + hit.dist * hit.ry
                        else
                            wallX = player.x + hit.dist * hit.rx
                        end
                        wallX = wallX - math.floor(wallX)
                        
                        if hit.side == 0 and hit.rx < 0 then wallX = 1.0 - wallX end
                        if hit.side == 1 and hit.ry > 0 then wallX = 1.0 - wallX end
                        
                        local paintingFrame = getPaintingFrameConfig(ts)
                        local pWidth = paintingFrame.width
                        local pHeight = paintingFrame.height
                        local pZOffset = paintingFrame.zOffset
                        
                        local margin = (1.0 - pWidth) / 2.0
                        
                        if wallX >= margin and wallX <= (1.0 - margin) then
                            -- 获取当前列在整幅画作上的横向 UV 进度 (0.0 ~ 1.0)
                            local texU = (wallX - margin) / pWidth
                            
                            local zTop = (pZOffset + pHeight / 2) * UNIT_PER_METER
                            local zBottom = (pZOffset - pHeight / 2) * UNIT_PER_METER
                            
                            local pDrawStart = (h / 2) - baseUnitHeight * (zTop - Z_PLAYER)
                            local pScreenHeight = baseUnitHeight * (zTop - zBottom)
                            
                            -- 【魔法步骤：物理深度偏置 Depth Bias】
                            -- 让画框比墙壁凸出 3 厘米，这样光照引擎会自动在墙上投射出真实的边框阴影！
                            local paintingDepth = correctedDist - paintingFrame.depthBias
                            
                            -- 切换到高端的画框着色器
                            love.graphics.setShader(gBufferPaintingShader)
                            
                            -- 传入所有需要的贴图和参数
                            gBufferPaintingShader:send("u_paintingTex", paintingAsset.image)
                            gBufferPaintingShader:send("u_frameTex", frameAlbedoTex)
                            gBufferPaintingShader:send("u_frameNormal", frameNormalTex)
                            gBufferPaintingShader:send("u_size", {pWidth, pHeight})
                            gBufferPaintingShader:send("u_frameThickness", paintingFrame.frameThickness)
                            gBufferPaintingShader:send("u_maxDepth", MAX_DEPTH)
                            
                            -- 传入当前光线信息
                            gBufferPaintingShader:send("u_currentU", texU)
                            gBufferPaintingShader:send("u_baseNormal", {nx, ny, nz}) 
                            gBufferPaintingShader:send("u_depth", paintingDepth)

                            -- 【新增】：传入玩家视线向量 (取反射线方向，使其从墙壁指向眼睛)
                            -- 虽然我们忽略了 Z 轴的高低视角变化，但在 Raycaster 中 X/Y 的视差已经足够产生完美的立体错觉了
                            gBufferPaintingShader:send("u_viewDir", {-hit.rx, -hit.ry, 0.0})
                            
                            love.graphics.setColor(1, 1, 1, 1)
                            
                            -- 为了能够利用 LÖVE 的 VaryingTexCoord，我们传入对应画作贴图的 1 像素竖切片。
                            -- Shader 会忽略它的颜色，只借用它的垂直 UV。
                            local texX = math.floor(texU * paintingAsset.width)
                            texX = math.max(0, math.min(paintingAsset.width - 1, texX)) 
                            
                            if paintingAsset.quads[texX] then
                                love.graphics.draw(
                                    paintingAsset.image,
                                    paintingAsset.quads[texX],
                                    x,
                                    pDrawStart,
                                    0,
                                    resolution,
                                    pScreenHeight / paintingAsset.height
                                )
                            end
                            
                            -- 切回普通墙壁 Shader...
                            love.graphics.setShader(gBufferShader)
                            gBufferShader:send("u_isFloor", false)
                            gBufferShader:send("u_normal", {nx, ny, nz})
                            gBufferShader:send("u_depth", correctedDist)
                            
                            -- 【检测鼠标悬停交互】
                            if not mouseState.showDetail then
                                if mx >= x and mx < (x + resolution) then
                                    if my >= pDrawStart and my <= (pDrawStart + pScreenHeight) then
                                        if hit.dist < 3.0 then
                                            hoveredPaintingThisFrame = {
                                                desc = ts.properties.desc or "未知的画作",
                                                detail = ts.properties.detail or "没有详细信息。"
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for i = x, x + resolution - 1 do zBuffer[math.floor(i)] = wallDistForZBuffer end
    end

    -- 4. 画 2D 精灵 (受限于 Z-Buffer 墙壁遮挡)
    love.graphics.setShader(gBufferSpriteShader)
    gBufferSpriteShader:send("u_maxDepth", MAX_DEPTH)

    for _, sprite in ipairs(sprites) do
        local dx = sprite.x - player.x
        local dy = sprite.y - player.y
        local dist = math.sqrt(dx*dx + dy*dy)
        local spriteAngle = math.atan2(dy, dx)
        local angleDiff = spriteAngle - player.dir
        
        while angleDiff > math.pi do angleDiff = angleDiff - 2 * math.pi end
        while angleDiff < -math.pi do angleDiff = angleDiff + 2 * math.pi end
        
        local correctedDist = dist * math.cos(angleDiff)
        
        -- ==========================================
        -- 【核心修复】：严格的视锥体剔除与近裁剪面
        -- ==========================================
        -- 1. 视锥体容差 (FOV Tolerance): 允许精灵在屏幕边缘外面一点点还能被渲染，防止因为贴图有宽度而突然消失
        local fovTolerance = 0.5 
        
        -- 2. 近裁剪面设定为 0.5 米 (correctedDist > 0.5)，防止除以极小值产生的无限拉伸畸变
        -- 3. 严格判定角度 math.abs(angleDiff) 必须在视锥体范围内
        if correctedDist > 0.5 and correctedDist < MAX_DEPTH and math.abs(angleDiff) < (player.fov / 2) + fovTolerance then
            
            local screenX = (0.5 * (angleDiff / (player.fov / 2)) + 0.5) * w
            local baseUnitHeight = h / correctedDist
            
            local drawHeight = baseUnitHeight * Z_STATUE
            local drawWidth = drawHeight * (sprite.texWidth / sprite.texHeight)
            
            local drawStartX = math.floor(screenX - drawWidth / 2)
            local drawEndX = math.floor(screenX + drawWidth / 2)
            local drawStartY = (h / 2) + baseUnitHeight * Z_PLAYER - drawHeight
            
            -- 缓存屏幕坐标系给鼠标 Hover 判定用
            sprite.drawStartX = drawStartX
            sprite.drawEndX = drawEndX
            sprite.drawStartY = drawStartY
            sprite.drawEndY = drawStartY + drawHeight
            sprite.dist = dist
            sprite.correctedDist = correctedDist

            -- 传参入 G-Buffer
            gBufferSpriteShader:send("u_spriteTex", sprite.texture)
            gBufferSpriteShader:send("u_normal", {-math.cos(spriteAngle), -math.sin(spriteAngle), 0})
            gBufferSpriteShader:send("u_depth", correctedDist)

            love.graphics.setColor(0.9, 0.9, 0.9)

            -- 切片绘制，Z-Buffer 遮挡剔除！
            for x = math.max(0, drawStartX), math.min(w - 1, drawEndX) do
                if correctedDist < (zBuffer[x] or MAX_DEPTH) then
                    local texX = math.floor((x - drawStartX) / drawWidth * sprite.texWidth)
                    texX = math.max(0, math.min(sprite.texWidth - 1, texX))
                    if sprite.quads[texX] then
                        love.graphics.draw(sprite.texture, sprite.quads[texX], x, drawStartY, 0, 1, drawHeight / sprite.texHeight)
                    end
                end
            end
        else
            -- 如果被剔除了，清空绘制数据，防止鼠标在看不见雕像的时候还能隔空触发调查！
            sprite.drawStartX = nil
            sprite.drawEndX = nil
        end
    end
end

-- ==================================================
-- deferred_light pass：读 G-Buffer 三张画布，写 gFinalComposite。
-- inputs = { gAlbedo, gNormal, gDepth }（管线按名解析，resize 重建后自动是新画布）
-- ==================================================
function drawLightingPass(_, inputs)
    local w, h = love.graphics.getDimensions()
    local gAlbedo, gNormal, gDepth = inputs[1], inputs[2], inputs[3]

    deferredLightingShader:send("u_normalTex", gNormal)
    deferredLightingShader:send("u_mapTex", gMapTex)
    deferredLightingShader:send("u_mapSize", {#map[1], #map})
    deferredLightingShader:send("u_depthTex", gDepth)
    deferredLightingShader:send("u_maxDepth", MAX_DEPTH)

    deferredLightingShader:send("u_playerPos", {player.x, player.y})
    deferredLightingShader:send("u_playerDir", player.dir)
    deferredLightingShader:send("u_fov", player.fov)
    deferredLightingShader:send("u_zPlayer", Z_PLAYER)
    deferredLightingShader:send("u_screenWidth", w)
    deferredLightingShader:send("u_screenHeight", h)

    deferredLightingShader:send("u_sunDirection", {0.8, -0.2, 0.25})
    -- deferredLightingShader:send("u_sunDirection", currentSunDir)
    deferredLightingShader:send("u_maxMapHeight", MAX_MAP_HEIGHT)
    if statueTex then
        deferredLightingShader:send("u_statueTex", statueTex)
    end

    love.graphics.draw(gAlbedo, 0, 0)
end

-- fxaa_capture / present 两个 pass 很薄，直接内联在 enter 的管线定义里。
function GameLayer:draw()
    GpuProfiler:beginFrame()
    pipeline:execute(self)
    -- execute 返回后已回到 backbuffer + 2D 基线状态，HUD 层直接叠加即可
end

-- ==================================================
-- 场景退出与显存清理
-- ==================================================
function GameLayer:exit()
    print("Exiting Raycast Scene...")
    
    -- 画布和 Shader 都已经交由 ResourceManager 的 unloadScene 自动 release 了！
    -- 这里我们只需要释放那些不在清单里、动态生成的特殊对象
    
    if skyMesh then skyMesh:release(); skyMesh = nil end
    if gMapTex then gMapTex:release(); gMapTex = nil end
    
    -- 断开对 ResourceManager 中资源的引用（好让 Lua 的垃圾回收机制顺利工作）
    gBufferShader = nil
    deferredLightingShader = nil
    gBufferSpriteShader = nil
    fxaaShader = nil
    pipeline = nil

    sprites = {}
    statueTex = nil
    paintingTextures = {}
    mouseState = ensureSceneUIState(self.sceneState)
    mouseState.hoveredSprite = nil
    mouseState.showDetail = false
    mouseState.detailSprite = nil
    mouseState.cursor.x = 0
    mouseState.cursor.y = 0
    map = {}
    player = {}

    if self.sceneState and self.sceneState.minimap then
        self.sceneState.minimap.map = nil
        self.sceneState.minimap.player = nil
        self.sceneState.minimap.visible = true
    end

    if self.sceneState and self.sceneState.ui then
        self.sceneState.ui.hoveredSprite = nil
        self.sceneState.ui.showDetail = false
        self.sceneState.ui.detailSprite = nil
        self.sceneState.ui.cursor = self.sceneState.ui.cursor or { x = 0, y = 0 }
        self.sceneState.ui.cursor.x = 0
        self.sceneState.ui.cursor.y = 0
    end
    
    AudioManager:clear()
end


function GameLayer:resize(width, height)
    if not pipeline then return end
    -- 所有 screenSized 画布（G-Buffer/合成/FXAA）统一重建，管线按名解析新引用。
    -- 旧实现只重建 FXAA 画布，G-Buffer 尺寸不随窗口变化——顺带修掉。
    ResourceManager:resetAllCanvases()
    if fxaaShader and fxaaShader:hasUniform("texelSize") then
        fxaaShader:send("texelSize", { 1.0 / width, 1.0 / height })
    end
end

return GameLayer

