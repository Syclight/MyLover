-- P0/P1 里程碑场景：真 3D 前向渲染 + 引擎级 RenderPipeline 验证。
-- 覆盖点：engine/math（Mat4/Vec3/Quat）、Camera3D（投影/视图/视锥剔除）、
-- RenderPipeline（声明式 pass、状态纪律、canvas 按名解析）、
-- ObjLoader/MeshBin（OBJ 与离线二进制两条网格加载路径）、
-- LevelMesh（关卡级 mesh/material/逐对象剔除）、
-- 固定步长模拟 + draw(alpha) 旋转插值、GpuProfiler 分趟计时。
--
-- 画面：一圈立方体网格 + 中心大立方体 + 顶上旋转的 OBJ 宝石，相机绕场景公转。
-- 左上角显示 绘制/剔除 数量——转动时能看到视锥剔除实时生效。
local BaseScene = require("engine.scenes.BaseScene")
local Diagnostics = require("engine.Diagnostics")
local ResourceManager = require("engine.managers.ResourceManager")
local Camera3D = require("engine.rendering.Camera3D")
local RenderPipeline = require("engine.rendering.RenderPipeline")
local ObjLoader = require("engine.rendering.ObjLoader")
local MeshBin = require("engine.rendering.MeshBin")
local LevelMesh = require("engine.rendering.LevelMesh")
local Mat4 = require("engine.math.Mat4")
local Vec3 = require("engine.math.Vec3")
local Quat = require("engine.math.Quat")
local Timestep = require("engine.utils.Timestep")
local GpuProfiler = require("engine.utils.GpuProfiler")
local Fuc = require("engine.utils.Fuc")
local CubeMesh = require("samples.cube3d.CubeMesh")

local Cube3DScene = BaseScene:extend()

local GRID = 7            -- GRID x GRID 的立方体阵
local SPACING = 2.5
local ORBIT_RADIUS = 9.0
local ORBIT_HEIGHT = 4.0
local SPIN_SPEED = 0.9    -- 自转（弧度/秒）
local ORBIT_SPEED = 0.25  -- 相机公转（弧度/秒）
local MODEL_DIR = "samples/cube3d/assets/models/"
local LEVEL_MANIFEST = "samples/cube3d/assets/levels/demo.lua"

-- 加载宝石网格：优先 tools/obj2mesh.js 离线转出的二进制（零解析），
-- 缺失则回退到运行时 OBJ 解析——开发迭代改 .obj 即可，发布跑离线转换。
local function loadGemMesh(texture)
    if love.filesystem.getInfo(MODEL_DIR .. "gem.mesh") then
        local mesh, header = MeshBin.load(MODEL_DIR .. "gem.mesh", texture)
        return mesh, header.boundingRadius, "meshbin"
    end
    local mesh, parsed = ObjLoader.load(MODEL_DIR .. "gem.obj", texture)
    return mesh, parsed.boundingRadius, "obj"
end

function Cube3DScene:enter()
    print("Scene: Enter Cube3D (P1 pipeline milestone)")
    love.mouse.setVisible(true)

    ResourceManager:loadManifest("samples/cube3d/assets/manifest.lua", "scene")
    self.shader = ResourceManager:get("cube3d_shader")
    local texture = ResourceManager:get("cube3d_texture")
    self.mesh = CubeMesh.create(texture)
    self.gemMesh, self.gemRadius, self.gemSource = loadGemMesh(texture)
    self.level, self.levelSource = LevelMesh.loadFromManifest(LEVEL_MANIFEST, ResourceManager)
    self.cubeMaterial = self.level.materials.accent or self.level.defaultMaterial
    self.gemMaterial = self.level.materials.wall or self.level.defaultMaterial
    print("Cube3D: gem mesh loaded via " .. self.gemSource)
    print("Cube3D: level mesh loaded via " .. self.levelSource)

    self.camera = Camera3D.new()
    self.camera:setPerspective(math.rad(60), nil, 0.1, 100)

    -- 固定步长模拟状态：保留上一步/当前步，draw 里用 alpha 插值（消除高刷抖动）
    self.spinPrev, self.spinCurr = 0, 0
    self.orbitPrev, self.orbitCurr = 0, 0
    self.spin, self.orbit = 0, 0 -- 本帧插值结果（execute 前算好，pass 里读）

    -- 复用的临时对象（热路径零分配纪律，同 DebugLayer 的做法）
    self.model = Mat4.new()
    self.levelModel = Mat4.new()
    self.normalMatrix = Mat4.new()
    self.levelNormalMatrix = Mat4.new()
    self.rotation = Quat.new()
    self.translation = Vec3.new()

    -- 方向光（指向光源）
    local light = Vec3.new(0.5, 0.9, 0.4)
    light:normalize()
    self.lightDir = { light.x, light.y, light.z }

    self.drawnCount, self.culledCount = 0, 0
    self.levelStats = { drawn = 0, culled = 0 }

    -- 场景诊断上报：剔除计数等进 F3 面板的 scene 段（DebugLayer 定时拉取），
    -- 场景 HUD 只留玩家向的提示，不再重复诊断数据
    Diagnostics.register("scene", function()
        return {
            string.format("cube3d drawn %d  culled %d", self.drawnCount, self.culledCount),
            "gem mesh: " .. self.gemSource,
            "level mesh: " .. self.levelSource .. " render " .. tostring(#self.level.objects),
            "colliders " .. tostring(#self.level.colliders) .. " triggers " .. tostring(#self.level.triggers),
        }
    end)

    -- ===== 渲染管线：3D 前向 pass 画进 canvas，present 合成到 backbuffer =====
    -- 深度/剔除状态由 pass 声明，出 pass 由 RenderPipeline 强制还原（RenderState.reset），
    -- 后续的 HUD/DebugLayer 拿到的永远是干净的 2D 基线状态。
    self.pipeline = RenderPipeline.new("cube3d")
    self.pipeline:addPass({
        name = "forward3d",
        output = "cube3d_canvas",
        depth = true,
        clear = { 0.07, 0.08, 0.11, 1 }, -- depth=true 时同时清深度
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
        input = "cube3d_canvas", -- 按名解析：resize 重建 canvas 后自动拿到新引用
        draw = function(_, inputs) love.graphics.draw(inputs[1]) end,
    })
end

function Cube3DScene:exit()
    Diagnostics.unregister("scene")
    -- 手动创建的 Mesh 不在 ResourceManager 里，需要自己释放；
    -- manifest 资源（贴图/shader/canvas）由场景资源作用域自动回收。
    if self.mesh then
        self.mesh:release()
        self.mesh = nil
    end
    if self.gemMesh then
        self.gemMesh:release()
        self.gemMesh = nil
    end
    if self.level then
        self.level:release()
        self.level = nil
    end
end

function Cube3DScene:update(dt)
    -- dt 是 Timestep 的固定步长；prev/curr 双份状态供渲染插值
    self.spinPrev = self.spinCurr
    self.orbitPrev = self.orbitCurr
    self.spinCurr = self.spinCurr + SPIN_SPEED * dt
    self.orbitCurr = self.orbitCurr + ORBIT_SPEED * dt
end

local function drawMesh(self, mesh, material, boundingRadius, x, y, z, spin, scale, phase)
    -- 视锥剔除：外接球测试，不可见直接跳过 draw call
    if not self.camera:isSphereVisible(x, y, z, boundingRadius * scale) then
        self.culledCount = self.culledCount + 1
        return
    end
    self.rotation:setEuler(spin + phase, spin * 0.7 + phase, 0)
    self.translation:set(x, y, z)
    self.model:setTRS(self.translation, self.rotation, scale)
    self.normalMatrix:setNormalFromModel(self.model)
    LevelMesh.applyMaterial(self.shader, mesh, material)
    self.shader:send("u_model", "column", self.model)
    self.shader:send("u_normalMatrix", "column", self.normalMatrix)
    love.graphics.draw(mesh)
    self.drawnCount = self.drawnCount + 1
end

-- forward3d pass 的绘制体。canvas 绑定/清屏/深度/剔除模式已由管线设置。
function Cube3DScene:drawWorld(pass)
    if pass and pass.viewportWidth and pass.viewportHeight then
        self.camera:setViewport(pass.viewportWidth, pass.viewportHeight)
    end
    self.shader:send("u_viewProj", "column", self.camera:getViewProjection())
    Fuc.safeSend(self.shader, "u_lightDir", self.lightDir)
    Fuc.safeSend(self.shader, "u_ambient", { 0.22, 0.22, 0.26 })
    Fuc.safeSend(self.shader, "u_cameraPos", { self.camera.position.x, self.camera.position.y, self.camera.position.z })

    local spin = self.spin
    self.levelStats.drawn, self.levelStats.culled = 0, 0
    self.levelModel:identity()
    self.levelNormalMatrix:setNormalFromModel(self.levelModel)
    self.level:drawObjects({
        camera = self.camera,
        shader = self.shader,
        model = self.levelModel,
        normalMatrix = self.levelNormalMatrix,
        stats = self.levelStats,
    })
    self.drawnCount = self.drawnCount + self.levelStats.drawn
    self.culledCount = self.culledCount + self.levelStats.culled

    -- 中心大立方体 + 头顶的 OBJ 宝石
    drawMesh(self, self.mesh, self.cubeMaterial, CubeMesh.BOUNDING_RADIUS, 0, 0.9, 0, spin, 1.8, 0)
    drawMesh(self, self.gemMesh, self.gemMaterial, self.gemRadius, 0, 3.2, 0, spin * 1.6, 1.4, 0.5)
    -- 地面阵列
    local half = (GRID - 1) * 0.5
    for gx = 0, GRID - 1 do
        for gz = 0, GRID - 1 do
            if gx ~= half or gz ~= half then
                local phase = (gx * GRID + gz) * 0.37
                drawMesh(self, self.mesh, self.cubeMaterial, CubeMesh.BOUNDING_RADIUS,
                    (gx - half) * SPACING, 0, (gz - half) * SPACING,
                    spin * 0.5, 0.8, phase)
            end
        end
    end
end

function Cube3DScene:draw(alpha)
    -- 渲染插值：Timestep.alpha 与传入的 alpha 一致，用引擎的插值辅助即可
    self.spin = Timestep:interpolateAngle(self.spinPrev, self.spinCurr, alpha)
    self.orbit = Timestep:interpolateAngle(self.orbitPrev, self.orbitCurr, alpha)

    self.camera:setPosition(
        math.cos(self.orbit) * ORBIT_RADIUS,
        ORBIT_HEIGHT,
        math.sin(self.orbit) * ORBIT_RADIUS)
    self.camera:lookAt(0, 0.5, 0)

    self.drawnCount, self.culledCount = 0, 0

    GpuProfiler:beginFrame()
    self.pipeline:execute(self)

    -- ===== HUD：execute 之后保证在 backbuffer + 2D 基线状态，直接叠加 =====
    -- 只留玩家向的操作提示；FPS/alpha/剔除计数等诊断数据都在 F3 面板
    -- （FPS/alpha 是 DebugLayer 固有项，剔除计数经 Diagnostics "scene" 段上报）。
    love.graphics.print("Cube3D (P1 pipeline)\nF3 debug overlay / Esc menu", 10, 10)
end

function Cube3DScene:resize()
    -- screenSized canvas 由 ResourceManager 重建；管线按名解析，无需重绑引用
    ResourceManager:resetAllCanvases()
    self.camera:resize()
end

return Cube3DScene
