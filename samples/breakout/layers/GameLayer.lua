local BaseLayer = require("engine.layers.BaseLayer")
local tiny = require("libs.tiny")
local Factory = require("samples.breakout.entities.Factory")
local Systems = require("samples.breakout.Systems")
local Camera = require("engine.rendering.Camera")
local PostProcess = require("samples.breakout.rendering.DamagePostProcess")
local EventBus = require("engine.utils.EventBus")
local ResourceManager = require("engine.managers.ResourceManager")

-- 继承 BaseLayer
local GameLayer = BaseLayer:extend()

function GameLayer:new()
    local instance = BaseLayer.new(self)
    instance.physicsWorld = nil
    instance.ecsWorld = nil
    return instance
end

-- 碰撞回调 (原本在 Scene 里的那个函数)
local function beginContact(ecsWorld, a, b, coll)
    local dataA = a:getUserData()
    local dataB = b:getUserData()
    if not dataA or not dataB then return end
    
    local brick = nil
    if type(dataA) == "table" and dataA.isBrick then brick = dataA end
    if type(dataB) == "table" and dataB.isBrick then brick = dataB end
    
    if brick and brick.toDestroy == nil then -- 简单防重
        brick.toDestroy = true
        ecsWorld:addEntity(brick)
        -- 这里稍微麻烦点，因为 beginContact 是全局回调，很难直接获取 self.ecsWorld
        -- 暂时我们可以通过全局变量或者闭包解决，这里假设 ecsWorld 还是能访问到的
        -- 或者更优雅的方式是：把 beginContact 放在 PhysicsSystem 内部处理
        -- 简单起见，我们暂且略过这里的 ecsWorld 通知，依靠 System 遍历 toDestroy 标记

        EventBus.emit("CameraShake", 5, 0.15)
        EventBus.emit("PlayerHurt")
    end
end

function GameLayer:enter()
    print("GameLayer: Enter")

    --- 1. 创建摄像机
    -- local w, h = love.graphics.getDimensions()
    -- self.camera = Camera.new(w/2, h/2, 1)
    self.camera = Camera.new(0, 0, 1)

    -- 监听震动请求
    self.eventSubscriptions = {}
    self.eventSubscriptions[#self.eventSubscriptions + 1] = EventBus.on("CameraShake", function(amount, duration)
        self.camera:shake(amount, duration)
    end)
    -- ...

    -- 2. 初始化后处理（资源由场景 Manifest/ResourceManager 持有）
    ResourceManager:loadManifest("samples/breakout/assets/manifest.lua")
    self.postProcess = PostProcess.new(
        ResourceManager:getScopeScene("breakout_post_canvas"),
        ResourceManager:getScopeScene("breakout_post_shader")
    )
    
    -- 3. 监听受击事件 (通过 EventBus)
    self.eventSubscriptions[#self.eventSubscriptions + 1] = EventBus.on("PlayerHurt", function()
        self.camera:shake(5, 0.3)      -- 物理震动
        self.postProcess:triggerDamage() -- 视觉滤镜 (变红+扭曲)
    end)
    
    -- 4. 物理初始化
    love.physics.setMeter(64)
    self.physicsWorld = love.physics.newWorld(0, 0, true)
    
    -- 5. ECS 初始化 (注意：Systems.Render() 必须在这里创建)
    self.ecsWorld = tiny.world(
        Systems.Input(),
        Systems.Physics(self.physicsWorld),
        Systems.Cleanup(),
        Systems.Render(self.camera)
    )

    self.physicsWorld:setCallbacks(function(a, b, coll)
        beginContact(self.ecsWorld, a, b, coll)
    end, nil, nil, nil)
    
    -- 6. 创建实体 (为了节省篇幅，这里简写，请把之前的 Factory 代码贴回来)
    local w, h = love.graphics.getDimensions()
    self.ecsWorld:addEntity(Factory.createPaddle(self.physicsWorld, w/2, h - 50, 100, 20))
    self.ecsWorld:addEntity(Factory.createBall(self.physicsWorld, w/2, h - 70, 10))
    -- ... 记得加上其他的墙和砖块 ...

    -- 7. 场景实体创建 (保持不变)
    -- local w, h = love.graphics.getDimensions()
    
    -- 墙壁
    self.ecsWorld:addEntity(Factory.createWall(self.physicsWorld, 0, 0, w, 10))
    self.ecsWorld:addEntity(Factory.createWall(self.physicsWorld, 0, 0, 10, h))
    self.ecsWorld:addEntity(Factory.createWall(self.physicsWorld, w-10, 0, 10, h))
    self.ecsWorld:addEntity(Factory.createWall(self.physicsWorld, 0, h-10, w, 10))

    -- 砖块
    local rows, cols = 6, 8
    local brickW, brickH, padding = 80, 30, 10
    local startX = (w - (cols * (brickW + padding))) / 2 + padding/2
    local startY = 50
    for r = 1, rows do
        for c = 1, cols do
            local bx = startX + (c-1) * (brickW + padding)
            local by = startY + (r-1) * (brickH + padding)
            local color = {(r/rows)*0.8+0.2, 0.4, (c/cols)*0.8+0.2}
            self.ecsWorld:addEntity(Factory.createBrick(self.physicsWorld, bx, by, brickW, brickH, color))
        end
    end
end

function GameLayer:exit()
    print("GameLayer: Exit")
    for i = #(self.eventSubscriptions or {}), 1, -1 do
        self.eventSubscriptions[i]()
    end
    self.eventSubscriptions = nil
    self.postProcess = nil
    if self.ecsWorld then
        self.ecsWorld:clearEntities()
        self.ecsWorld = nil
    end
    if self.physicsWorld then
        self.physicsWorld:destroy()
        self.physicsWorld = nil
    end
end


function GameLayer:resize(width, height)
    if not self.postProcess then return end
    local canvas = ResourceManager:resetCanvas("breakout_post_canvas", width, height)
    self.postProcess:setCanvas(canvas)
end

function GameLayer:update(dt)
    if self.postProcess then self.postProcess:update(dt) end
    if self.camera then
        self.camera:update(dt)
        -- 如果你想做 RPG 跟随，可以在这里写：
        -- self.camera:lookAt(playerX, playerY)
    end

    if self.ecsWorld then
        -- 只运行非渲染系统
        self.ecsWorld:update(dt, tiny.rejectAny("isRenderSystem"))
    end
end

function GameLayer:draw()
    -- if self.ecsWorld then
    --     -- 只运行渲染系统
    --     self.ecsWorld:update(love.timer.getDelta(), tiny.requireAll("isRenderSystem"))
    -- end

    -- 1. 开始录制 (所有内容画到 Canvas 上)
    if self.postProcess then self.postProcess:start() end
    
        -- 2. 运行 ECS 渲染系统 (包含 Camera 处理)
        if self.ecsWorld then
            self.ecsWorld:update(love.timer.getDelta(), tiny.requireAll("isRenderSystem"))
        end
    
    -- 3. 停止录制 -> 应用 Shader -> 画到屏幕
    if self.postProcess then self.postProcess:stop() end
end

return GameLayer
