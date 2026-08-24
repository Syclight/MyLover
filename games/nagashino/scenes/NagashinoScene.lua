local BaseScene = require("engine.scenes.BaseScene")
local BattleCrowd = require("games.nagashino.rendering.BattleCrowd")
local BattleCasualties = require("games.nagashino.rendering.BattleCasualties")
local DroppedWeapons = require("games.nagashino.rendering.DroppedWeapons")
local CraterDecals = require("engine.rendering.CraterDecals")
local BattleEffects = require("games.nagashino.rendering.BattleEffects")
local BattlefieldMaterial = require("games.nagashino.rendering.BattlefieldMaterial")
local BattlefieldStamps = require("games.nagashino.rendering.BattlefieldStamps")
local BattleSimulation = require("games.nagashino.gameplay.BattleSimulation")
local Camera3D = require("engine.rendering.Camera3D")
local Diagnostics = require("engine.Diagnostics")
local Environment = require("engine.rendering.Environment")
local Fuc = require("engine.utils.Fuc")
local GpuProfiler = require("engine.utils.GpuProfiler")
local LevelMesh = require("engine.rendering.LevelMesh")
local Mat4 = require("engine.math.Mat4")
local ParticleSystem = require("engine.rendering.ParticleSystem")
local RenderPipeline = require("engine.rendering.RenderPipeline")
local ResourceManager = require("engine.managers.ResourceManager")
local ShadowMap = require("engine.rendering.ShadowMap")
local StrategyCamera = require("engine.rendering.StrategyCamera")
local Vec3 = require("engine.math.Vec3")

local NagashinoScene = BaseScene:extend()

local LEVEL_MANIFEST = "games/nagashino/assets/levels/nagashino.lua"

local SCRIPT_BEATS = {
    { time = 0.0, trigger = "command_view_trigger", text = "设乐原视点：织田、德川联军依马防柵布置火枪阵。" },
    { time = 5.0, trigger = "takeda_charge_lane_trigger", text = "武田骑兵沿泥路展开冲锋，试图突破中央防线。" },
    { time = 10.0, trigger = "oda_fireline_trigger", text = "火枪阵进入轮射节奏，马防柵把冲击切成数段。" },
    { time = 16.0, trigger = "oda_fireline_trigger", text = "冲锋势头被削弱，战场焦点转向栅栏前的消耗。" },
}

local TARGET_BOUNDS = { minX = -35, maxX = 35, minZ = -20, maxZ = 20 }
local CAMERA_BOUNDS = { minX = -62, maxX = 62, minZ = -42, maxZ = 42 }
local BATTLEFIELD_STATE_BOUNDS = { minX = -64, maxX = 64, minZ = -44, maxZ = 44 }

local function triggerCenter(trigger)
    local center = trigger and trigger.center
    if not center then return 0, 0, 0 end
    return center[1] or 0, center[2] or 0, center[3] or 0
end

function NagashinoScene:enter()
    ResourceManager:loadManifest("games/nagashino/assets/manifest.lua", "scene")
    self.shader = ResourceManager:get("nagashino_shader")
    self.shadowShader = ResourceManager:get("nagashino_shadow_shader")
    self.crowdSpriteShader = ResourceManager:get("nagashino_crowd_sprite_shader")
    self.crowdShadowShader = ResourceManager:get("nagashino_crowd_shadow_shader")
    self.fallenSpriteShader = ResourceManager:get("nagashino_fallen_sprite_shader")
    self.corpse3dShader = ResourceManager:get("nagashino_corpse3d_shader")
    self.droppedWeaponShader = ResourceManager:get("nagashino_dropped_weapon_shader")
    self.craterDecalShader = ResourceManager:get("engine_crater_decal_shader")
    self.particleShader = ResourceManager:get("engine_particle3d_shader")
    self.hudFont = ResourceManager:get("font_NotoSerifSC-Regular_18")
    self.level, self.levelSource = LevelMesh.loadFromManifest(LEVEL_MANIFEST, ResourceManager)
    self.battle = BattleSimulation.new()
    self.stamps = BattlefieldStamps.new(ResourceManager:get("nagashino_battlefield_state"), BATTLEFIELD_STATE_BOUNDS)
    self.particles = ParticleSystem.new({
        shader = self.particleShader,
        texture = ResourceManager:get("nagashino_smoke"),
        capacity = 650,
    })
    self.dustParticles = ParticleSystem.new({
        shader = self.particleShader,
        texture = ResourceManager:get("nagashino_smoke"),
        capacity = 1200,
        -- 尘土是视觉体积，不应被单位/地形深度完全切掉。
        depthMode = "always",
    })
    self.casualties = BattleCasualties.new(ResourceManager:get("nagashino_fallen_casualties_sheet"),
        ResourceManager:get("nagashino_fallen_casualties_edge"), self.corpse3dShader, self.crowdShadowShader, 96)
    self.weapons = DroppedWeapons.new(self.droppedWeaponShader, 96)
    self.craters = CraterDecals.new(ResourceManager:get("nagashino_crater_dirt_color"), self.craterDecalShader, 160)
    self.effects = BattleEffects.new(self.particles, self.dustParticles, self.stamps, self.casualties, self.craters, self.weapons)
    self.crowd = BattleCrowd.new(self.battle, {
        cavalry = ResourceManager:get("nagashino_takeda_cavalry_sheet"),
        cavalryDeath = ResourceManager:get("nagashino_takeda_cavalry_death_sheet"),
        ashigaru = ResourceManager:get("nagashino_alliance_ashigaru_sheet"),
        teppo = ResourceManager:get("nagashino_alliance_teppo_sheet"),
    }, {
        sprite = self.crowdSpriteShader,
        shadow = self.crowdShadowShader,
    })

    self.camera = Camera3D.new()
    self.camera:setPerspective(math.rad(52), nil, 0.1, 320)
    self.strategyCamera = StrategyCamera.new(self.camera, {
        yaw = -0.38,
        pitch = math.rad(20),
        distance = 38,
        minDistance = 9,
        maxDistance = 72,
        minPitch = math.rad(18),
        maxPitch = math.rad(66),
        maxEyeHeight = 58,
        targetBounds = TARGET_BOUNDS,
        eyeBounds = CAMERA_BOUNDS,
        targetX = 0,
        targetY = 1.2,
        targetZ = 0,
        edgePadding = 2.5,
    })
    self.dragging = false
    self.model = Mat4.new()
    self.normalMatrix = Mat4.new()
    self.stats = { drawn = 0, culled = 0 }
    self.environment = Environment.new({
        skyShader = ResourceManager:get("engine_procedural_sky"),
        skyTexture = ResourceManager:get("nagashino_sky_day_cc0"),
        skyRotation = 0.5,
        lightDir = Vec3.new(-0.85, 0.42, 0.10),
        ambient = { 0.055, 0.060, 0.065, 1 },
        skyIrradiance = { 0.28, 0.36, 0.48, 1 },
        horizonIrradiance = { 0.30, 0.28, 0.22, 1 },
        groundIrradiance = { 0.16, 0.12, 0.075, 1 },
        sunIntensity = 2.7,
        exposure = 1.12,
        fogStart = 40,
        fogDensity = 0.011,
        fogHeightFalloff = 0.018,
        skyTop = { 0.18, 0.38, 0.72, 1 },
        skyMid = { 0.48, 0.67, 0.88, 1 },
        horizon = { 0.72, 0.76, 0.73, 1 },
        groundHaze = { 0.43, 0.49, 0.39, 1 },
        sunColor = { 1.0, 0.78, 0.42, 1 },
        cloudCoverage = 0.57,
        cloudScale = 1.18,
        cloudSpeed = 0.003,
    })
    self.shadowMap = ShadowMap.new(ResourceManager:get("nagashino_shadow_map"), self.shadowShader, {
        range = 74,
        distance = 96,
        near = 1,
        far = 196,
        strength = 0.62,
        bias = 0.0022,
        fadeStart = 52,
    })
    self.time = 0
    self.activeBeatIndex = 1
    self.focusIndex = 1
    self.interactionMessage = "拖拽旋转，滚轮拉近/拉远，WASD 平移，Tab 切换触发区，E 聚焦/互动。"
    self.messageTimer = 0
    self.triggerByName = {}
    for _, trigger in ipairs(self.level.triggers) do
        self.triggerByName[trigger.name] = trigger
    end
    self.scriptTriggers = {}
    local seenTriggers = {}
    for _, beat in ipairs(SCRIPT_BEATS) do
        local trigger = self.triggerByName[beat.trigger]
        if trigger and not seenTriggers[trigger.name] then
            self.scriptTriggers[#self.scriptTriggers + 1] = trigger
            seenTriggers[trigger.name] = true
        end
    end

    Diagnostics.register("scene", function()
        local beat = SCRIPT_BEATS[self.activeBeatIndex]
        return {
            "nagashino source: " .. self.levelSource,
            "render objects: " .. tostring(#self.level.objects),
            "colliders: " .. tostring(#self.level.colliders),
            "triggers: " .. tostring(#self.level.triggers),
            "active trigger: " .. tostring(beat and beat.trigger or "none"),
            string.format("camera distance %.1f / %.1f",
                self.strategyCamera.effectiveDistance, self.strategyCamera.distance),
            string.format("drawn %d culled %d", self.stats.drawn, self.stats.culled),
            string.format("crowd instances %d visible %d culled", #self.crowd.batches,
                self.crowd.visible, self.crowd.culled),
            string.format("battlefield stamps %d", self.stamps.stampCount),
            string.format("fallen %d bodies %d", #self.casualties.casualties, self.casualties.visible),
            string.format("effects %d/%d dust %d/%d emitted %d", self.particles.active,
                self.particles.visible, self.dustParticles.active, self.dustParticles.visible,
                self.effects.dustEmitted),
        }
    end)

    self.pipeline = RenderPipeline.new("nagashino")
    self.pipeline:addPass({
        name = "sun_shadow",
        output = "nagashino_shadow_map",
        depth = true,
        clear = { 1, 1, 1, 1 },
        state = {
            shader = self.shadowShader,
            depthMode = { "lequal", true },
            cullMode = "back",
            winding = "ccw",
        },
        draw = function(scene) scene:drawShadows() end,
    })
    self.pipeline:addPass({
        name = "forward3d",
        output = "nagashino_canvas",
        depth = true,
        clear = { 0, 0, 0, 0 },
        state = {
            shader = self.shader,
            depthMode = { "lequal", true },
            cullMode = "back",
            winding = function(scene) return scene.camera:frontFaceWinding() end,
        },
        draw = function(scene, _, pass) scene:drawWorld(pass) end,
    })
    self.pipeline:addPass({
        name = "present",
        input = "nagashino_canvas",
        draw = function(scene, inputs)
            scene.environment:drawSkybox(nil, nil, scene.camera, scene.time)
            love.graphics.draw(inputs[1])
        end,
    })
end

function NagashinoScene:exit()
    Diagnostics.unregister("scene")
    if self.level then
        self.level:release()
        self.level = nil
    end
    if self.crowd then
        self.crowd:release()
        self.crowd = nil
    end
    if self.particles then
        self.particles:release()
        self.particles = nil
    end
    if self.dustParticles then
        self.dustParticles:release()
        self.dustParticles = nil
    end
    if self.casualties then
        self.casualties:release()
        self.casualties = nil
    end
    if self.weapons then
        self.weapons:release()
        self.weapons = nil
    end
    if self.craters then
        self.craters:release()
        self.craters = nil
    end
    self.effects = nil
    self.stamps = nil
end

function NagashinoScene:update(dt)
    self.battle:update(dt)
    self.effects:update(self.battle, dt)
    self.casualties:update(dt)
    self.weapons:update(dt)
    self.stamps:collect(self.battle)
    self.time = self.time + dt
    if self.messageTimer > 0 then
        self.messageTimer = math.max(0, self.messageTimer - dt)
    end

    local keyboard = love.keyboard
    if not keyboard or not keyboard.isScancodeDown then return end

    local forwardX = -math.cos(self.strategyCamera.yaw)
    local forwardZ = -math.sin(self.strategyCamera.yaw)
    local rightX = -forwardZ
    local rightZ = forwardX
    local speed = (keyboard.isScancodeDown("lshift", "rshift") and 20 or 11) * dt
    local moveX, moveZ = 0, 0
    if keyboard.isScancodeDown("w", "up") then
        moveX, moveZ = moveX + forwardX, moveZ + forwardZ
    end
    if keyboard.isScancodeDown("s", "down") then
        moveX, moveZ = moveX - forwardX, moveZ - forwardZ
    end
    if keyboard.isScancodeDown("d", "right") then
        moveX, moveZ = moveX + rightX, moveZ + rightZ
    end
    if keyboard.isScancodeDown("a", "left") then
        moveX, moveZ = moveX - rightX, moveZ - rightZ
    end
    local len = math.sqrt(moveX * moveX + moveZ * moveZ)
    if len > 0 then
        local scale = speed / len
        self.strategyCamera:pan(moveX * scale, moveZ * scale)
    end
end

function NagashinoScene:beatIndexForTrigger(triggerName)
    for index, beat in ipairs(SCRIPT_BEATS) do
        if beat.trigger == triggerName then return index end
    end
    return 1
end

function NagashinoScene:focusTrigger(index, announce)
    local trigger = self.scriptTriggers[index]
    if not trigger then return false end

    self.focusIndex = index
    self.activeBeatIndex = self:beatIndexForTrigger(trigger.name)
    local x, y, z = triggerCenter(trigger)
    self.strategyCamera:setTarget(x, y + 1.35, z)
    if announce then
        local beat = SCRIPT_BEATS[self.activeBeatIndex]
        self.interactionMessage = beat and beat.text or ("已聚焦：" .. trigger.name)
        self.messageTimer = 4
    end
    return true
end

function NagashinoScene:focusNextTrigger()
    if #self.scriptTriggers == 0 then return false end
    local nextIndex = (self.focusIndex % #self.scriptTriggers) + 1
    return self:focusTrigger(nextIndex, true)
end

function NagashinoScene:interactFocusedTrigger()
    if #self.scriptTriggers == 0 then return false end
    return self:focusTrigger(self.focusIndex, true)
end

function NagashinoScene:resetCamera()
    self.strategyCamera.yaw = -0.38
    self.strategyCamera.pitch = math.rad(20)
    self.strategyCamera.distance = 38
    self.strategyCamera:setTarget(0, 1.2, 0)
    self.activeBeatIndex = 1
    self.focusIndex = 1
    self.interactionMessage = "镜头已复位。"
    self.messageTimer = 3
end

function NagashinoScene:updateCamera()
    self.strategyCamera:update()
end

function NagashinoScene:drawWorld(pass)
    if pass and pass.viewportWidth and pass.viewportHeight then
        self.camera:setViewport(pass.viewportWidth, pass.viewportHeight)
    end

    self.model:identity()
    self.normalMatrix:setNormalFromModel(self.model)
    self.stats.drawn, self.stats.culled = 0, 0

    self.shader:send("u_viewProj", "column", self.camera:getViewProjection())
    self.environment:send(self.shader)
    self.shadowMap:send(self.shader)
    self.shader:send("u_hasBattlefieldState", 1)
    self.shader:send("u_battlefieldState", ResourceManager:get("nagashino_battlefield_state"))
    self.shader:send("u_mudTrackTexture", ResourceManager:get("nagashino_mud_cc0_color"))
    self.shader:send("u_craterDirtTexture", ResourceManager:get("nagashino_crater_dirt_color"))
    self.shader:send("u_craterNormalTexture", ResourceManager:get("nagashino_crater_dirt_normal"))
    self.shader:send("u_craterRoughnessTexture", ResourceManager:get("nagashino_crater_dirt_roughness"))
    self.shader:send("u_battlefieldBounds", {
        BATTLEFIELD_STATE_BOUNDS.minX,
        BATTLEFIELD_STATE_BOUNDS.minZ,
        BATTLEFIELD_STATE_BOUNDS.maxX,
        BATTLEFIELD_STATE_BOUNDS.maxZ,
    })
    -- safeSend：u_time/u_cameraPos 若被 GLSL 编译器优化掉（死代码消除），
    -- 裸 send 会直接抛错把场景打崩
    Fuc.safeSend(self.shader, "u_cameraPos",
        { self.camera.position.x, self.camera.position.y, self.camera.position.z })
    Fuc.safeSend(self.shader, "u_time", self.time)

    self.level:drawObjects({
        camera = self.camera,
        shader = self.shader,
        model = self.model,
        normalMatrix = self.normalMatrix,
        stats = self.stats,
        -- 本作专属的逐材质 uniform（战场状态开关 + 水面）；引擎只发通用 PBR 字段
        materialSender = BattlefieldMaterial.send,
    })
    self.craters:draw(self.camera, self.environment)
    self.casualties:draw3D(self.camera, self.environment)
    self.weapons:draw(self.camera, self.environment)
    self.crowd:draw(self.camera, self.environment)
    self.dustParticles:draw(self.camera, self.environment)
    self.particles:draw(self.camera, self.environment)
end

function NagashinoScene:drawShadows()
    self.model:identity()
    self.shadowShader:send("u_lightViewProj", "column", self.shadowMap.viewProjection)
    self.level:drawObjects({
        shader = self.shadowShader,
        model = self.model,
    })
    -- 人群单元约一米高，远小于树/栅栏；不进 shadow map 可省去一整次高频动态网格绘制。
end

function NagashinoScene:draw()
    GpuProfiler:beginFrame()
    self:updateCamera()
    self.crowd:update(self.camera, self.battle.time)
    self.stamps:render()
    self.shadowMap:update(self.environment.lightDir, self.camera.target)
    self.pipeline:execute(self)
    local beat = SCRIPT_BEATS[self.activeBeatIndex]
    local trigger = beat and self.triggerByName[beat.trigger] or nil
    local info = self.battle:statusText()
    local triggerLine = trigger and ("trigger: " .. trigger.name) or "trigger: none"
    local message = self.messageTimer > 0 and self.interactionMessage
        or "鼠标拖拽旋转 / 滚轮缩放 / WASD 平移 / 空格暂停 / R 重开 / Tab 切换视点"
    local oldFont = love.graphics.getFont()
    if self.hudFont then love.graphics.setFont(self.hudFont) end
    love.graphics.print("长筱之战：设乐原\n" .. info .. "\n"
        .. string.format("联军 %d  武田 %d", self.battle:aliveCount("oda") + self.battle:aliveCount("tokugawa"), self.battle:aliveCount("takeda"))
        .. "\n" .. triggerLine .. "\n" .. message, 10, 10)
    if oldFont then love.graphics.setFont(oldFont) end
end

function NagashinoScene:mousepressed(x, y, button)
    if button == 1 or button == 2 then
        self.dragging = true
        return true
    end
    return BaseScene.mousepressed(self, x, y, button)
end

function NagashinoScene:mousereleased(x, y, button)
    if button == 1 or button == 2 then
        self.dragging = false
        return true
    end
    return BaseScene.mousereleased(self, x, y, button)
end

function NagashinoScene:mousemoved(x, y, dx, dy)
    if not self.dragging then
        return BaseScene.mousemoved(self, x, y, dx, dy)
    end
    self.strategyCamera:orbitPixels(dx, dy)
    return true
end

function NagashinoScene:wheelmoved(_, y)
    if y == 0 then return false end
    self.strategyCamera:zoom(y)
    return true
end

function NagashinoScene:keypressed(key, scancode, isrepeat)
    if BaseScene.keypressed(self, key, scancode, isrepeat) then return true end
    if key == "tab" then
        return self:focusNextTrigger()
    elseif key == "e" then
        return self:interactFocusedTrigger()
    elseif key == "home" then
        self:resetCamera()
        return true
    elseif key == "space" then
        self.battle.paused = not self.battle.paused
        self.interactionMessage = self.battle.paused and "战斗已暂停。" or "战斗继续。"
        self.messageTimer = 2
        return true
    elseif key == "r" then
        self.battle:reset()
        self.crowd:reset(self.battle)
        self.stamps:clear()
        self.effects:clear()
        self.interactionMessage = "战役已重开。"
        self.messageTimer = 2
        return true
    end
    return false
end

function NagashinoScene:resize()
    ResourceManager:resetAllCanvases()
    self.camera:resize()
end

return NagashinoScene
