local Tests = {}

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function testEventBus()
    package.loaded["engine.utils.EventBus"] = nil
    local bus = require("engine.utils.EventBus")
    local calls = 0
    local unsubscribe = bus.on("ping", function(value) calls = calls + value end)
    bus.emit("ping", 2)
    unsubscribe()
    bus.emit("ping", 2)
    equal(calls, 2, "EventBus unsubscribe")
    bus.clear()
end

local function testTimestep()
    package.loaded["engine.utils.Timestep"] = nil
    local timestep = require("engine.utils.Timestep")
    timestep:reset()
    timestep:setTickRate(60)
    local steps = 0
    timestep:advance(1 / 30, function() steps = steps + 1 end)
    equal(steps, 2, "fixed timestep catch-up")
    equal(timestep:interpolate(0, 10, 0.25), 2.5, "interpolate accepts explicit alpha")
end

local function testInputMap()
    local InputMap = require("engine.input.InputMap")
    local input = InputMap.new({
        move_left = { "a", { device = "key", scancode = "left" } },
        fire = { { device = "mouse", button = 1 }, { device = "gamepad", button = "a" } },
    })
    local consumed, actions = input:keypressed("a", "a", false)
    equal(consumed, true, "input map consumes bound key")
    equal(actions[1], "move_left", "input map returns action")
    equal(input:isDown("move_left"), true, "input action is down")
    equal(input:consumePressed("move_left"), true, "input pressed edge is consumable")
    equal(input:consumePressed("move_left"), false, "input pressed edge is consumed once")
    input:keyreleased("a", "a")
    equal(input:wasReleased("move_left"), true, "input release edge is tracked")
    input:resetFrame()
    input:mousepressed(0, 0, 1)
    equal(input:wasPressed("fire"), true, "input map supports mouse bindings")
end

local function testInputRecorder()
    local Recorder = require("engine.input.InputRecorder")
    local recorder = Recorder.new()
    recorder:startRecording()
    recorder:record("keypressed", "a")
    recorder:update(0.5)
    recorder:record("keyreleased", "a")
    local events = recorder:stopRecording()
    equal(#events, 2, "input recorder stores events")

    local calls = {}
    recorder:startPlayback(events, function(method, key)
        calls[#calls + 1] = method .. ":" .. key
    end)
    recorder:update(0.1)
    equal(table.concat(calls, ","), "keypressed:a", "input recorder replays first event")
    recorder:update(0.5)
    equal(table.concat(calls, ","), "keypressed:a,keyreleased:a", "input recorder replays timed events")
    equal(recorder:isPlaying(), false, "input recorder stops after playback")
end

local function testSceneInstances()
    local BaseScene = require("engine.scenes.BaseScene")
    local Example = BaseScene:extend()
    local a, b = Example:new(), Example:new()
    a.value = 7
    equal(b.value, nil, "scene instances must not share state")
end

local function testSceneResourceScopes()
    local BaseScene = require("engine.scenes.BaseScene")
    local SceneManager = require("engine.managers.SceneManager")
    local ResourceManager = require("engine.managers.ResourceManager")
    local Example = BaseScene:extend()
    function Example:enter(label)
        self.label = label
        self.resourceStore = ResourceManager.scene
        ResourceManager.scene.owner = label
    end
    function Example:resume()
        equal(ResourceManager.scene, self.resourceStore, "resume restores scene resource scope")
    end

    local base, overlay = Example:new(), Example:new()
    SceneManager.switch(base, "base")
    SceneManager.push(overlay, "overlay")
    if base.resourceStore == overlay.resourceStore then error("stacked scenes share a resource scope") end
    SceneManager.pop()
    equal(ResourceManager.scene.owner, "base", "pop restores underlying resources")
    SceneManager.quit()
end

local function testSceneInputDispatch()
    local BaseScene = require("engine.scenes.BaseScene")
    local SceneManager = require("engine.managers.SceneManager")
    local calls = {}

    local Base = BaseScene:extend()
    function Base:keypressed(key)
        calls[#calls + 1] = "base:" .. key
        return true
    end

    local Overlay = BaseScene:extend()
    function Overlay:keypressed(key)
        calls[#calls + 1] = "overlay:" .. key
        return key == "consume"
    end

    local BlockingOverlay = BaseScene:extend()
    function BlockingOverlay:keypressed(key)
        calls[#calls + 1] = "blocking:" .. key
        return false
    end
    function BlockingOverlay:allowsGlobalShortcuts()
        return false
    end

    SceneManager.switch(Base:new())
    SceneManager.push(Overlay:new())
    SceneManager.keypressed("pass")
    equal(table.concat(calls, ","), "overlay:pass,base:pass", "unconsumed input bubbles down")
    calls = {}
    SceneManager.keypressed("consume")
    equal(table.concat(calls, ","), "overlay:consume", "consumed input stops bubbling")
    SceneManager.push(BlockingOverlay:new())
    calls = {}
    SceneManager.keypressed("blocked")
    equal(table.concat(calls, ","), "blocking:blocked", "blocking overlay prevents bubbling")
    SceneManager.quit()
end

local function testTransitionScene()
    local BaseScene = require("engine.scenes.BaseScene")
    local SceneManager = require("engine.managers.SceneManager")
    local TransitionScene = require("engine.scenes.TransitionScene")
    local Target = BaseScene:extend()
    local entered = false
    function Target:enter() entered = true end
    local transition = TransitionScene:new({ nextScene = Target:new(), duration = 1 })
    SceneManager.switch(transition)
    equal(transition:progress(), 0, "transition starts at zero progress")
    SceneManager.update(1)
    equal(entered, true, "transition switches to target scene")
    SceneManager.quit()
end

local function testManifestShaderModules()
    local ResourceManager = require("engine.managers.ResourceManager")
    local scope = ResourceManager:createSceneScope("manifest-test")
    ResourceManager:activateSceneScope(scope)
    ResourceManager:loadManifest("samples/breakout/assets/manifest.lua")
    equal(ResourceManager:getScopeScene("breakout_post_canvas") ~= nil, true, "manifest canvas")
    equal(ResourceManager:getScopeScene("breakout_post_shader") ~= nil, true, "module-backed shader")
    ResourceManager:releaseSceneScope(scope)
end

local function testNagashinoManifestAssets()
    local ResourceManager = require("engine.managers.ResourceManager")
    local manifestSource = assert(love.filesystem.read("games/nagashino/assets/manifest.lua"))
    equal(manifestSource:find("samples/", 1, true) == nil, true,
        "Nagashino manifest is independent from sample asset paths")
    equal(manifestSource:find("games.nagashino.assets.shaders.Battlefield3D", 1, true) ~= nil, true,
        "Nagashino uses its own PBR variant, not the bare engine shader")
    local scope = ResourceManager:createSceneScope("nagashino-manifest-test")
    ResourceManager:activateSceneScope(scope)
    ResourceManager:loadManifest("games/nagashino/assets/manifest.lua")
    equal(ResourceManager:getScopeScene("nagashino_fallen_casualties_sheet") ~= nil, true,
        "Nagashino casualty atlas loads")
    equal(ResourceManager:getScopeScene("nagashino_takeda_cavalry_death_sheet") ~= nil, true,
        "Nagashino cavalry death sheet loads")
    equal(ResourceManager:getScopeScene("nagashino_fallen_sprite_shader") ~= nil, true,
        "Nagashino fallen-sprite shader compiles")
    equal(ResourceManager:getScopeScene("nagashino_corpse3d_shader") ~= nil, true,
        "Nagashino textured fallen-proxy shader compiles")
    equal(ResourceManager:getScopeScene("engine_crater_decal_shader") ~= nil, true,
        "engine crater decal shader compiles")
    local BattleCasualties = require("games.nagashino.rendering.BattleCasualties")
    local casualties = BattleCasualties.new(
        ResourceManager:get("nagashino_fallen_casualties_sheet"),
        ResourceManager:get("nagashino_fallen_casualties_edge"),
        ResourceManager:get("nagashino_corpse3d_shader"),
        ResourceManager:get("nagashino_crowd_shadow_shader"),
        2)
    casualties:add({ x = 0, z = 0, role = "ashigaru", seed = 0 })
    equal(#casualties.casualties, 1, "Nagashino fallen proxy batch accepts casualties")
    casualties:release()
    local BattleSimulation = require("games.nagashino.gameplay.BattleSimulation")
    local BattleCrowd = require("games.nagashino.rendering.BattleCrowd")
    local battle = BattleSimulation.new()
    local crowd = BattleCrowd.new(battle, {
        cavalry = ResourceManager:get("nagashino_takeda_cavalry_sheet"),
        cavalryDeath = ResourceManager:get("nagashino_takeda_cavalry_death_sheet"),
        ashigaru = ResourceManager:get("nagashino_alliance_ashigaru_sheet"),
        teppo = ResourceManager:get("nagashino_alliance_teppo_sheet"),
    }, {
        sprite = ResourceManager:get("nagashino_crowd_sprite_shader"),
        shadow = ResourceManager:get("nagashino_crowd_shadow_shader"),
    })
    local staleUnit = crowd.batches[1].units[1]
    battle:reset()
    crowd:reset(battle)
    equal(crowd.batches[1].units[1] ~= staleUnit, true,
        "Nagashino crowd rebinds to reset formation units")
    crowd:release()
    ResourceManager:releaseSceneScope(scope)
end

local function testResourceManagerAsyncManifestAndLookup()
    local ResourceManager = require("engine.managers.ResourceManager")
    local scope = ResourceManager:createSceneScope("async-manifest-test")
    ResourceManager:activateSceneScope(scope)

    ResourceManager.global.lookup_priority = "global"
    ResourceManager.scene.lookup_priority = "scene"
    equal(ResourceManager:get("lookup_priority"), "scene", "scene resources shadow globals by default")
    ResourceManager.global.lookup_priority = nil

    local tasks = ResourceManager:createTasksFromManifest("engine/assets/manifest/global.lua", "scene")
    for _, task in ipairs(tasks) do task() end
    equal(ResourceManager:getScopeScene("font_default_12") ~= nil, true, "async manifest loads default font")
    equal(ResourceManager:getScopeScene("font_NotoSerifSC-Regular_18") ~= nil, true,
        "async manifest preserves font size/scope/name")
    equal(ResourceManager:getScopeScene("engine_procedural_sky") ~= nil, true,
        "global manifest loads the procedural sky shader")

    local breakoutScope = ResourceManager:createSceneScope("async-breakout-manifest-test")
    ResourceManager:activateSceneScope(breakoutScope)
    tasks = ResourceManager:createTasksFromManifest("samples/breakout/assets/manifest.lua", "scene")
    for _, task in ipairs(tasks) do task() end
    equal(ResourceManager:getScopeScene("breakout_post_canvas") ~= nil, true, "async manifest loads canvas")
    equal(ResourceManager:getScopeScene("breakout_post_shader") ~= nil, true, "async manifest loads shader")

    local stats = ResourceManager:debugStats()
    equal(stats.scene.canvases >= 1, true, "resource stats count canvases")
    equal(stats.scene.shaders >= 1, true, "resource stats count shaders")

    ResourceManager:releaseSceneScope(breakoutScope)
    ResourceManager:releaseSceneScope(scope)
end

local function testManifestValidation()
    local ResourceManager = require("engine.managers.ResourceManager")
    local ok, message = pcall(function()
        ResourceManager:createTasksFromManifest("tests/fixtures/bad_manifest_duplicate.lua", "scene")
    end)
    equal(ok, false, "duplicate manifest keys are rejected")
    equal(tostring(message):find("duplicate resource key", 1, true) ~= nil, true,
        "manifest duplicate error explains the problem")
end

local function testInventoryLifecycle()
    local Inventory = require("games.surveillance.gameplay.Inventory")
    local state = Inventory.new(2)
    local added, slot = Inventory.add(state, { id = "remote", name = "Remote" })
    equal(added, true, "inventory add")
    equal(slot, 1, "inventory first free slot")
    Inventory.select(state, slot)
    equal(Inventory.isSelected(state, "remote"), true, "inventory selection")
    Inventory.deselect(state)
    local cycledItem, cycledSlot = Inventory.cycle(state, 1)
    equal(cycledItem.id, "remote", "inventory cycle enters occupied slot")
    equal(cycledSlot, 1, "inventory cycle starts at first slot")
    equal(Inventory.isSelected(state, "remote"), true, "inventory cycle selection")
    local emptyItem, emptySlot = Inventory.cycle(state, 1)
    equal(emptyItem, nil, "inventory cycle can enter empty slot")
    equal(emptySlot, 2, "inventory keeps empty slot selected")
    equal(state.selectedSlot, 2, "empty slot retains selection outline")
    Inventory.cycle(state, 1)
    equal(state.selectedSlot, 1, "inventory cycle wraps across all slots")
    Inventory.remove(state, "remote")
    equal(Inventory.has(state, "remote"), false, "inventory remove")
    equal(state.selectedSlot, nil, "removing selected item clears selection")
end

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function filesBelow(directory, suffixes, output)
    output = output or {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(directory)) do
        local path = directory .. "/" .. name
        local info = love.filesystem.getInfo(path)
        if info and info.type == "directory" then
            filesBelow(path, suffixes, output)
        else
            for _, suffix in ipairs(suffixes) do
                if name:sub(-#suffix) == suffix then
                    output[#output + 1] = path
                    break
                end
            end
        end
    end
    return output
end

local function luaFilesBelow(directory, output)
    return filesBelow(directory, { ".lua" }, output)
end

-- 引擎源码里出现游戏包名 = 边界破了。
-- 这条比 require 检查更宽：着色器模块是返回 GLSL 字符串的 .lua，不 require 任何东西，
-- 游戏专属的 uniform 和采样逻辑曾经就是这样绕过 require 检查混进 engine/ 的
-- （engine/assets/shaders/Pbr3D.lua 一度带着 nagashino 的战场状态与弹坑贴图）。
local function testEngineShaderBoundary()
    local packageNames = {}
    for _, root in ipairs({ "games", "samples" }) do
        for _, name in ipairs(love.filesystem.getDirectoryItems(root)) do
            local info = love.filesystem.getInfo(root .. "/" .. name)
            if info and info.type == "directory" then
                packageNames[#packageNames + 1] = name:lower()
            end
        end
    end
    equal(#packageNames > 0, true, "game/sample packages discovered")

    for _, path in ipairs(filesBelow("engine", { ".lua", ".glsl" })) do
        local source = readFile(path):lower()
        for _, package in ipairs(packageNames) do
            equal(source:find(package, 1, true), nil,
                "engine must not mention the '" .. package .. "' package: " .. path)
        end
    end
end

local function testEngineGameBoundary()
    local mainSource = readFile("main.lua")
    for _, path in ipairs(luaFilesBelow("engine")) do
        local source = readFile(path)
        equal(source:match("require%s*%(%s*['\"]games%."), nil,
            "engine must not import a concrete game: " .. path)
        equal(source:find("tests.run", 1, true), nil,
            "engine must not import the workspace test suite: " .. path)
    end
    equal(mainSource:find("src%.scenes", 1, false), nil, "main must not import concrete scenes")

    local project = require("project")
    equal(type(project.testModule), "string", "project-owned test module")
    local game = require(project.game)
    equal(type(game.id), "string", "selected game id")
    equal(type(game.createInitialScene), "function", "selected game scene factory")
    equal(game:createInitialScene({}).__isSceneInstance, true, "game creates a scene instance")

    local catalog = require("samples.catalog")
    for id, modulePath in pairs(catalog) do
        equal(type(modulePath), "string", "sample catalog module path: " .. id)
        local sample = require(modulePath)
        equal(sample.id, id, "sample catalog id: " .. id)
        equal(type(sample.createInitialScene), "function", "sample Game contract: " .. id)
    end

    for _, root in ipairs({ "engine", "games", "samples" }) do
        for _, path in ipairs(luaFilesBelow(root)) do
            equal(readFile(path):match("require%s*%(%s*['\"]src%."), nil,
                "canonical code must not depend on the removed src namespace: " .. path)
        end
    end
end

local function testDiagnosticsRegistry()
    local Diagnostics = require("engine.Diagnostics")
    Diagnostics.register("test", function() return { value = 7 } end)
    equal(Diagnostics.read("test").value, 7, "diagnostic provider")
    Diagnostics.unregister("test")
    equal(Diagnostics.read("test"), nil, "diagnostic unregister")
end

local function testServiceRegistry()
    local ServiceRegistry = require("engine.services.ServiceRegistry")
    local registry = ServiceRegistry.new()
    local calls = {}
    local service = {
        start = function(_, context) calls[#calls + 1] = "start:" .. context.name end,
        update = function(_, dt) calls[#calls + 1] = "update:" .. dt end,
        stop = function() calls[#calls + 1] = "stop" end,
    }
    equal(registry:register("example", service), service, "service registration")
    equal(registry:require("example"), service, "service lookup")
    registry:startAll({ name = "test" })
    registry:update(0.25)
    registry:stopAll()
    equal(table.concat(calls, ","), "start:test,update:0.25,stop", "service lifecycle")
end

local function testSaveService()
    local SaveService = require("engine.services.SaveService")
    local files = {}
    local storage = {
        createDirectory = function() return true end,
        write = function(path, content) files[path] = content return true end,
        read = function(path) return files[path] end,
        getInfo = function(path) return files[path] and { type = "file" } or nil end,
        remove = function(path) files[path] = nil return true end,
        getDirectoryItems = function(root)
            local items = {}
            for file in pairs(files) do
                local name = file:match("^" .. root .. "/(.+)$")
                if name then items[#items + 1] = name end
            end
            return items
        end,
    }
    local saves = SaveService.new({ root = "unit", version = 3, storage = storage })
    saves:save("slot_1", { score = 42 }, { label = "Unit" })
    equal(saves:exists("slot_1"), true, "save service reports existing slot")
    local payload, envelope = saves:load("slot_1")
    equal(payload.score, 42, "save service loads payload")
    equal(envelope.version, 3, "save service stores version")
    equal(saves:list()[1], "slot_1", "save service lists slots")
    saves:delete("slot_1")
    equal(saves:exists("slot_1"), false, "save service deletes slots")
end

local function testLLMGameBoundary()
    local LLMService = require("engine.services.llm.LLMService")
    local service = LLMService.new({ backendModule = "engine.services.llm.backends.OllamaBackend" })
    equal(service:debugStats().started, false, "llm service starts idle")

    local TerminalSession = require("games.surveillance.llm.TerminalSession")
    local requests = {}
    local fake = {
        chat = function(_, options)
            requests[#requests + 1] = options
            return 1
        end,
    }
    local transcript = {}
    local session = TerminalSession.new({ name = "Test", persona = "Persona" }, {}, transcript, fake)
    equal(session:send("Hello"), true, "game session accepts injected llm service")
    equal(#requests, 1, "game session delegates to llm service")
end

local function testLLMCancelStopsWorker()
    local LLMService = require("engine.services.llm.LLMService")
    local service = LLMService.new({
        backendModule = "tests.llm.FakeCancelBackend",
        stopTimeout = 1.0,
    })
    service:start()
    local id = service:chat({ messages = { { role = "user", content = "hello" } } })
    service:cancel(id)
    for _ = 1, 20 do
        service:update()
        love.timer.sleep(0.01)
    end
    equal(service:debugStats().pending, 0, "llm cancel clears pending request")
    service:stop()
    local stats = service:debugStats()
    equal(stats.started, false, "llm stop clears started flag")
    equal(stats.error, nil, "llm worker stops after cancel broadcast")
end

local function testPlayerController()
    local PlayerController = require("games.surveillance.systems.PlayerController")
    local controller = PlayerController.new({ mouseSensitivity = 0.01, maxPitch = 1.0 })
    local oldIsDown, oldIsScancodeDown = love.keyboard.isDown, love.keyboard.isScancodeDown
    love.keyboard.isDown = function() return false end
    love.keyboard.isScancodeDown = function(key) return key == "w" end
    local world = {
        player = { x = 0, y = 0, dir = 0, pitch = 0, baseHeight = 1, height = 1 },
        moveSpeed = 2, strafeSpeed = 1, time = 0, playerSitting = false,
        mouseLookEnabled = true,
    }
    function world:_canOccupy() return true end
    controller:update(world, 0.5)
    love.keyboard.isDown, love.keyboard.isScancodeDown = oldIsDown, oldIsScancodeDown
    equal(world.player.x, 1, "player controller forward movement")
    controller:mousemoved(world, 10, -5)
    equal(world.player.dir, 0.1, "player controller mouse yaw")
    equal(world.player.pitch, 0.05, "player controller mouse pitch")
end

local function testFurniturePoseSystem()
    local PostureSystem = require("games.surveillance.systems.PostureSystem")
    local poses = PostureSystem.new({
        chairSeatOffset = 0.6, chairSmoothing = 7,
        seatedEyeHeight = 1.12, maxPitch = 1.0,
    })
    local world = {
        tileSizeMeters = 0.5,
        chairPos = { x = 3, y = 4 }, computerPos = { x = 3, y = 2 },
        player = { x = 8, y = 9, dir = 0.3, pitch = 0.1, baseHeight = 1.28, height = 1.28 },
    }
    poses:setupChair(world)
    poses:moveChairToComputer(world)
    poses:sitDown(world)
    equal(world.playerSitting, true, "chair pose enters seated state")
    equal(world.player.height, 1.12, "chair pose eye height")
    poses:standUp(world)
    equal(world.player.x, 8, "chair pose restores player position")
    equal(world.player.height, 1.28, "chair pose restores eye height")
end

local function testInteractionSystem()
    local InteractionSystem = require("games.surveillance.systems.InteractionSystem")
    local Inventory = require("games.surveillance.gameplay.Inventory")
    local inventory = Inventory.new(2)
    local _, slot = Inventory.add(inventory, { id = "ac_remote", icon = "remote" })
    Inventory.select(inventory, slot)
    local world = {
        sceneState = { apartment = {}, inventory = inventory },
        playerSitting = false,
    }
    function world:_computePlacement() return { x = 1, y = 2, z = 0.5 } end
    InteractionSystem.new():update(world, nil)
    equal(world.sceneState.apartment.canPlaceRemote, true, "selected remote computes placement")
    equal(world.remotePlacement.z, 0.5, "interaction stores placement preview")

    local furnitureHit = { target = { priority = 3 }, distance = 0.2 }
    local itemHit = { target = { priority = 7 }, distance = 0.5 }
    equal(InteractionSystem.isBetterHit(itemHit, furnitureHit), true,
        "surface item interaction outranks furniture volume")
    equal(InteractionSystem.isBetterHit(furnitureHit, itemHit), false,
        "furniture does not hide a targeted surface item")
end

local function testPlacementSystem()
    local PlacementSystem = require("games.surveillance.systems.PlacementSystem")
    local world = {
        player = { x = 0, y = 0, dir = 0, pitch = -math.pi * 0.25, height = 1 },
        tileSizeMeters = 0.5,
        placeSurfaces = {},
    }
    function world:_isBlockedAt() return false end
    local placement = PlacementSystem.new({ reach = 2 }):compute(world)
    equal(placement.z, 0, "placement system floor height")
    equal(placement.x > 1.9, true, "placement system projects view ray")
end

local function testItemWorldSystem()
    local Inventory = require("games.surveillance.gameplay.Inventory")
    local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")
    local ItemWorldSystem = require("games.surveillance.systems.ItemWorldSystem")
    local inventory = Inventory.new(2)
    local _, slot = Inventory.add(inventory, { id = "book_test", name = "Test", icon = "book", bookIndex = 1 })
    Inventory.select(inventory, slot)
    local world = {
        sceneState = { inventory = inventory, apartment = {}, monologue = PlayerMonologue.new() },
        bookPlacement = { x = 2, y = 3, z = 0.5 },
        placedBooks = {}, interactables = {},
        bookshelfMasks = { left = 63, right = 63 },
        bookSlots = { left = {}, right = {} },
    }
    local items = ItemWorldSystem.new({ maxPlacedBooks = 12, placementReach = 1.8 })
    items:placeBook(world)
    equal(#world.placedBooks, 1, "item world places a book")
    equal(Inventory.has(inventory, "book_test"), false, "placed book leaves inventory")
    world.sceneState.apartment.pickupTarget = world.placedBooks[1].interactable
    items:pickUpHovered(world)
    equal(#world.placedBooks, 0, "item world removes picked world book")
    equal(Inventory.has(inventory, "book_test"), true, "picked world book returns to inventory")
    equal(world.sceneState.monologue.current ~= nil, true, "picking up a book triggers player monologue")

    local remoteInventory = Inventory.new(2)
    local _, remoteSlot = Inventory.add(remoteInventory, { id = "ac_remote", icon = "remote" })
    Inventory.select(remoteInventory, remoteSlot)
    local remoteTarget = { interaction = "pickup", bottomHeight = 0, targetHeight = 0.9 }
    local remoteWorld = {
        sceneState = { inventory = remoteInventory }, remoteInteractable = remoteTarget,
        interactables = {}, remotePlacement = {},
    }
    items:commitRemote(remoteWorld, 2, 3, 0.52)
    equal(remoteTarget.bottomHeight, 0.52, "placed remote hitbox starts at support surface")
    equal(remoteTarget.targetHeight, 0.64, "placed remote hitbox remains pickable above support surface")

    local initialStyles = 0
    for index = 1, 6 do initialStyles = initialStyles + index * 8 ^ (index - 1) end
    local shelfInventory = Inventory.new(2)
    local sourceBook = {
        interaction = "pickup_book", itemId = "book_four", desc = "Book Four",
        bookIndex = 4, shelfKey = "left", slotIndex = 4,
    }
    local targetSlot = {
        interaction = "pickup_book", shelfKey = "right", slotIndex = 1,
    }
    local shelfWorld = {
        sceneState = { inventory = shelfInventory, apartment = { pickupTarget = sourceBook } },
        bookshelfMasks = { left = 63, right = 62 },
        bookshelfBookStyles = { left = initialStyles, right = initialStyles },
        bookSlots = { left = {}, right = { [1] = targetSlot } },
        placedBooks = {}, interactables = { sourceBook },
    }
    items:pickUpHovered(shelfWorld)
    shelfWorld.sceneState.apartment.bookShelfTarget = { shelfKey = "right" }
    items:placeBook(shelfWorld)
    equal(shelfWorld.bookshelfBookStyles.right % 8, 4,
        "returned book keeps its own color when inserted into another slot")
end

local function testPlayerMonologue()
    local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")
    local state = PlayerMonologue.new()
    equal(PlayerMonologue.say(state, "first", { key = "once", duration = 1 }), true,
        "monologue accepts a line")
    equal(PlayerMonologue.say(state, "duplicate", { key = "once" }), false,
        "monologue suppresses repeated keyed lines")
    PlayerMonologue.say(state, "second", { duration = 1 })
    PlayerMonologue.update(state, 1)
    equal(state.current.text, "second", "monologue advances queued lines")
    local text, alpha = PlayerMonologue.visible(state)
    equal(text, "second", "monologue exposes current text")
    equal(alpha, 0, "new queued line begins faded out")
end

local function testHUDMessages()
    local HUDMessages = require("games.surveillance.gameplay.HUDMessages")
    local PlayerMonologue = require("games.surveillance.gameplay.PlayerMonologue")
    local Inventory = require("games.surveillance.gameplay.Inventory")
    local messages = HUDMessages.new()
    local inventory = Inventory.new(1, messages)
    Inventory.add(inventory, { id = "remote", name = "Remote" })
    local toast = HUDMessages.visible(messages, "toast")
    equal(toast.text, "Remote", "inventory routes pickup notices through HUD messages")
    equal(toast.title, "获得物品", "inventory pickup notice uses item card title")

    local monologue = PlayerMonologue.new(messages)
    PlayerMonologue.say(monologue, "I should remember this.", { key = "thought" })
    local line = HUDMessages.visible(messages, "monologue")
    equal(line.text, "I should remember this.", "monologue routes through HUD messages")
    equal(PlayerMonologue.say(monologue, "duplicate", { key = "thought" }), false,
        "monologue still suppresses repeated keyed messages")
end

local function testGameClockAndRest()
    local GameClock = require("games.surveillance.gameplay.GameClock")
    local RestSystem = require("games.surveillance.gameplay.RestSystem")
    local clock = GameClock.new({ startMinutes = 6 * 60, minutesPerSecond = 1 })
    equal(GameClock.format(clock), "06:00", "game starts at wake time")
    local date = GameClock.date(clock)
    equal(string.format("%04d-%02d-%02d", date.year, date.month, date.day), "1984-06-12",
        "game starts on configured calendar date")
    equal(date.weekdayName, "星期二", "calendar weekday matches start date")
    local hands = GameClock.handDirections(clock)
    equal(math.abs(hands.minute[1]) < 0.000001, true, "six o'clock minute hand horizontal")
    equal(hands.minute[2] > 0.999999, true, "six o'clock minute hand points to twelve")
    equal(math.abs(hands.hour[1]) < 0.000001, true, "six o'clock hour hand horizontal")
    equal(hands.hour[2] < -0.999999, true, "six o'clock hour hand points to six")
    clock.absoluteMinutes = clock.absoluteMinutes + 0.9
    local stableHands = GameClock.handDirections(clock)
    equal(math.abs(stableHands.minute[1] - hands.minute[1]) < 0.000001, true,
        "wall clock remains stable within the displayed minute")
    GameClock.update(clock, 60)
    equal(GameClock.format(clock), "07:00", "real seconds advance game minutes")

    local leapClock = GameClock.new({
        startMinutes = 6 * 60,
        startDate = { year = 1984, month = 2, day = 28 },
    })
    leapClock.absoluteMinutes = leapClock.absoluteMinutes + 24 * 60
    equal(GameClock.date(leapClock).day, 29, "calendar handles leap day")

    local rest = RestSystem.new()
    RestSystem.update(rest, clock, "lie", 2.5)
    equal(rest.drowsiness, 0.5, "bed drowsiness grows over five seconds")
    RestSystem.update(rest, clock, nil, 0)
    equal(rest.drowsiness, 0, "leaving bed clears drowsiness")
    RestSystem.update(rest, clock, "lie", 5)
    equal(rest.menuOpen, true, "five seconds in bed opens rest menu")
    equal(RestSystem.keypressed(rest, clock, "escape"), true, "escape dismisses rest menu")
    RestSystem.update(rest, clock, "lie", 0.1)
    equal(rest.drowsiness, 0, "dismissed rest keeps vision clear while still in bed")
    equal(rest.menuOpen, false, "dismissed rest does not immediately reopen")
    RestSystem.update(rest, clock, nil, 0)
    RestSystem.update(rest, clock, "lie", 5)
    equal(RestSystem.keypressed(rest, clock, "2"), true, "rest menu consumes duration choice")
    equal(GameClock.format(clock), "09:00", "two-hour rest advances clock")

    clock.absoluteMinutes = 23 * 60 + 30
    GameClock.restHours(clock, 2)
    equal(GameClock.day(clock), 2, "rest crossing midnight advances day")
    equal(GameClock.format(clock), "06:00", "rest crossing midnight wakes at six")

    clock.absoluteMinutes = 24 * 60
    local forced = RestSystem.update(RestSystem.new(), clock, nil, 0)
    equal(forced, "forced_sleep", "midnight curfew forces sleep")
    equal(GameClock.format(clock), "06:00", "forced sleep wakes at six")
end

local function testReadingSystem()
    local ReadingSystem = require("games.surveillance.gameplay.ReadingSystem")
    local Books = require("games.surveillance.data.books")
    local state = ReadingSystem.new()
    equal(ReadingSystem.openBook(state, { icon = "remote" }), false,
        "reading rejects non-book items")
    equal(ReadingSystem.openBook(state, { icon = "book", bookIndex = 6 }), true,
        "reading opens selected book")
    equal(ReadingSystem.pageCount(state), #Books.get(6).pages, "reading uses book pages")
    ReadingSystem.keypressed(state, "right")
    equal(state.page, 2, "reading turns forward")
    ReadingSystem.wheelmoved(state, 1)
    equal(state.page, 1, "reading wheel turns backward")
    ReadingSystem.keypressed(state, "escape")
    equal(state.open, false, "reading closes with escape")
end

local function testComputerOS()
    local ComputerOS = require("games.surveillance.computer.ComputerOS")
    local state = ComputerOS.new()
    ComputerOS.beginSession(state)
    equal(state.booted, true, "computer OS boots on first session")
    equal(state.activeApp, "desktop", "computer OS opens desktop")
    ComputerOS.update(state, 2)
    equal(state.bootTimer, 0, "computer OS completes boot timer")
    ComputerOS.keypressedDesktop(state, "right")
    equal(state.selected, 2, "desktop moves app selection")
    ComputerOS.keypressedDesktop(state, "return")
    equal(state.activeApp, "archives", "desktop launches selected app")
    equal(ComputerOS.backToDesktop(state), true, "application returns to desktop")
    equal(ComputerOS.backToDesktop(state), false, "desktop back exits computer scope")
end

local function testEvidenceLog()
    local GameClock = require("games.surveillance.gameplay.GameClock")
    local EvidenceLog = require("games.surveillance.gameplay.EvidenceLog")
    local clock = GameClock.new({ startMinutes = 20 * 60 })
    local log = EvidenceLog.new()
    local entry = EvidenceLog.add(log, clock, {
        frequency = "83.4",
        speaker = "甲",
        profession = "教师",
        counterpart = "乙",
        activity = "晚间通话",
        topic = "一只信封",
        quote = "  明天不要从正门走。  ",
    })
    equal(entry.quote, "明天不要从正门走。", "evidence trims captured quote")
    equal(EvidenceLog.count(log), 1, "evidence stores an entry")
    equal(EvidenceLog.unreviewedCount(log), 1, "evidence starts unread")
    EvidenceLog.markReviewed(log)
    equal(EvidenceLog.unreviewedCount(log), 0, "evidence can be reviewed")
end

local function testComputerOSViews()
    local ResourceManager = require("engine.managers.ResourceManager")
    local GameClock = require("games.surveillance.gameplay.GameClock")
    local TerminalLayer = require("games.surveillance.layers.TerminalLayer")
    ResourceManager:loadManifest("engine/assets/manifest/global.lua", "global")
    local fakeLLM = {
        chat = function() return 1 end,
        cancel = function() end,
        debugStats = function() return { started = true, pending = 0 } end,
    }
    local state = {
        apartment = { mode = "terminal" },
        clock = GameClock.new(),
        terminal = {},
    }
    local layer = TerminalLayer:new(state, fakeLLM)
    layer:enter()
    layer:openOS()
    layer:draw()
    layer:update(2)
    for _, app in ipairs({ "desktop", "archives", "evidence", "notes", "system", "surveillance" }) do
        state.terminal.os.activeApp = app
        layer:draw()
    end
    layer:stopAll()
    ResourceManager:unloadAll()
    equal(state.terminal.os.booted, true, "computer OS views render through boot and applications")
end

local function testTimedIntercepts()
    local GameClock = require("games.surveillance.gameplay.GameClock")
    local InterceptDirector = require("games.surveillance.llm.InterceptDirector")
    local channelDefs = require("games.surveillance.data.channels")
    local residents = require("games.surveillance.data.residents")
    local byId = {}
    for _, resident in ipairs(residents) do byId[resident.id] = resident end

    local pending, nextId = {}, 0
    local fakeLLM = {
        chat = function(_, _, handlers)
            nextId = nextId + 1
            pending[nextId] = handlers
            return nextId
        end,
        cancel = function(_, id) pending[id] = nil end,
    }
    local function minimumRandom(a, _b)
        if a == nil then return 0 end
        return a
    end
    local function resolve(def)
        local channel = {}
        for key, value in pairs(def) do channel[key] = value end
        channel.a, channel.b = byId[def.a], byId[def.b]
        return channel
    end

    equal(InterceptDirector.isWithinWindow(6 * 60, channelDefs[3].windows[1]), true,
        "intercept schedule opens at configured time")
    equal(InterceptDirector.isWithinWindow(8 * 60, channelDefs[3].windows[1]), false,
        "intercept schedule closes outside routine")

    local clock = GameClock.new({ startMinutes = 6 * 60 })
    local transcript = {}
    local evidence = require("games.surveillance.gameplay.EvidenceLog").new()
    local director = InterceptDirector.new(transcript, fakeLLM, clock, evidence, { random = minimumRandom })
    director:monitor(resolve(channelDefs[3]))
    clock.absoluteMinutes = clock.absoluteMinutes + 1
    director:tick(1)
    equal(director.state, "conversation", "scheduled channel can begin a finite call")
    equal(director.callLength, 2, "call length is bounded")
    pending[director.activeId].onDone("第一句日常通讯。")
    clock.absoluteMinutes = clock.absoluteMinutes + 1
    director:tick(1)
    pending[director.activeId].onDone("第二句日常通讯。")
    equal(director.state, "cooldown", "call automatically ends after its allotted turns")
    equal(director.busy, false, "ended call leaves no generation running")
    equal(#evidence.entries, 2, "clue calls are archived as evidence snippets")

    local quietClock = GameClock.new({ startMinutes = 10 * 60 })
    local quietTranscript = {}
    local quiet = InterceptDirector.new(quietTranscript, fakeLLM, quietClock, { random = minimumRandom })
    quiet:monitor(resolve(channelDefs[3]))
    quietClock.absoluteMinutes = quietClock.absoluteMinutes + 1
    quiet:tick(1)
    equal(quiet.state, "waiting", "channel stays silent outside daily routine")
    equal(quiet.activeStatus, "频道静默", "quiet channel reports silence")
end

local function testCharacterProfiles()
    local profiles = require("games.surveillance.data.character_profiles")
    package.loaded["games.surveillance.data.residents"] = nil
    local residents = require("games.surveillance.data.residents")
    equal(#residents, 6, "all resident profiles are exposed")
    local seen = {}
    for _, resident in ipairs(residents) do
        local profile = resident.profile
        equal(seen[resident.id], nil, "resident id is unique: " .. resident.id)
        seen[resident.id] = true
        equal(profile, profiles[resident.id], "resident references structured profile")
        equal(type(profile.biography), "string", "profile biography: " .. resident.id)
        equal(#profile.biography > 300, true, "profile biography is detailed: " .. resident.id)
        equal(#profile.relationships >= 4, true, "profile relationships: " .. resident.id)
        equal(#profile.secrets >= 4, true, "profile layered secrets: " .. resident.id)
        equal(#profile.dialogueExamples >= 2, true, "profile dialogue examples: " .. resident.id)
        equal(resident.persona:find("【角色档案】", 1, true) ~= nil, true,
            "persona includes profile prompt: " .. resident.id)
        equal(resident.persona:find("知识边界", 1, true) ~= nil, true,
            "persona includes knowledge boundaries: " .. resident.id)
        equal(#resident.persona > 1200, true, "persona has sufficient reference detail: " .. resident.id)
    end
end

local function testApartmentRendererHistoryPolicy()
    local Renderer = require("games.surveillance.rendering.ApartmentRenderer")
    local renderer = Renderer.new({
        sharpness = 0.16, staticHistoryWeight = 0.7,
        maxPositionDelta = 0.01, maxDirectionDelta = 0.1,
        maxFurniture = 8, maxPlacedBooks = 12, maxPointLights = 6,
    })
    equal(renderer:historyWeight(0, 0, false), 0, "renderer rejects unavailable history")
    equal(renderer:historyWeight(0, 0, true), 0.7, "renderer keeps static history")
    equal(renderer:historyWeight(0.02, 0, true), 0, "renderer rejects moving history")
end

local function testTinyPhysicsIntegration()
    local PhysicsStepSystem = require("engine.integrations.tiny.PhysicsStepSystem")
    local world = { elapsed = 0 }
    function world:update(dt) self.elapsed = self.elapsed + dt end
    local system = PhysicsStepSystem(world)
    system:update(0.25)
    equal(world.elapsed, 0.25, "physics step advances injected world")
    system.enabled = false
    system:update(0.25)
    equal(world.elapsed, 0.25, "disabled physics step does not advance")

    local replacement = { elapsed = 0 }
    function replacement:update(dt) self.elapsed = self.elapsed + dt end
    system:setPhysicsWorld(replacement)
    system.enabled = true
    system:update(0.5)
    equal(replacement.elapsed, 0.5, "physics step supports world replacement")
end

local function testTinyPhysicsCleanupIntegration()
    local CleanupSystem = require("engine.integrations.tiny.PhysicsCleanupSystem")
    local destroyed, removed = false, false
    local entity = {
        toDestroy = true,
        body = {
            isDestroyed = function() return destroyed end,
            destroy = function() destroyed = true end,
        },
    }
    local system = CleanupSystem()
    system.world = { removeEntity = function(_, value) removed = value == entity end }
    system:process(entity)
    equal(destroyed, true, "physics cleanup destroys body")
    equal(removed, true, "physics cleanup removes ECS entity")
end

local function testObjectInheritance()
    local Object = require("engine.utils.Object")
    local Animal = Object:extend()
    function Animal:speak() return "..." end
    local Dog = Animal:extend()
    function Dog:speak() return "wang" end
    local dog = Dog:new({ name = "d" })
    equal(dog.name, "d", "Object:new keeps instance fields")
    equal(dog:speak(), "wang", "subclass overrides method")
    equal(Animal:new():speak(), "...", "base class method reachable")
end

local function testBaseSceneLayerHelpers()
    local BaseScene = require("engine.scenes.BaseScene")
    local scene = BaseScene:extend():new()
    local log = {}
    local bottom = {
        enter = function() log[#log + 1] = "enter:bottom" end,
        keypressed = function(_, key) log[#log + 1] = "bottom:" .. key end,
        exit = function() log[#log + 1] = "exit:bottom" end,
    }
    local top = {
        enter = function() log[#log + 1] = "enter:top" end,
        keypressed = function(_, key)
            log[#log + 1] = "top:" .. key
            return key == "consume"
        end,
        exit = function() log[#log + 1] = "exit:top" end,
    }
    scene:addLayer(bottom)
    scene:addLayer(top)
    equal(table.concat(log, ","), "enter:bottom,enter:top", "addLayer calls enter in order")
    log = {}
    equal(scene:dispatchToLayers("keypressed", "consume"), true, "layer consumption is reported")
    equal(table.concat(log, ","), "top:consume", "consumed input stops at top layer")
    log = {}
    equal(scene:dispatchToLayers("keypressed", "pass"), false, "unconsumed input is reported")
    equal(table.concat(log, ","), "top:pass,bottom:pass", "unconsumed input reaches lower layers")
    log = {}
    scene:exitLayers()
    equal(table.concat(log, ","), "exit:top,exit:bottom", "layers exit in reverse order")
    equal(#scene.layers, 0, "exitLayers clears the stack")
end

local function testSceneSubscriptionCleanup()
    -- 同时重载 EventBus 与 BaseScene，保证两者引用同一个总线实例
    package.loaded["engine.utils.EventBus"] = nil
    package.loaded["engine.scenes.BaseScene"] = nil
    local BaseScene = require("engine.scenes.BaseScene")
    local EventBus = require("engine.utils.EventBus")
    local SceneManager = require("engine.managers.SceneManager")

    local calls = 0
    local Example = BaseScene:extend()
    function Example:enter()
        self:on("ping", function() calls = calls + 1 end)
    end

    SceneManager.switch(Example:new())
    EventBus.emit("ping")
    equal(calls, 1, "scene subscription receives events")
    SceneManager.quit()
    EventBus.emit("ping")
    equal(calls, 1, "scene exit cancels its subscriptions")
    EventBus.clear()
end

local function testSceneEnterFailure()
    local BaseScene = require("engine.scenes.BaseScene")
    local SceneManager = require("engine.managers.SceneManager")
    local Broken = BaseScene:extend()
    function Broken:enter() error("boom") end

    SceneManager.switch(Broken:new())
    if SceneManager.current() == nil then
        error("switch enter failure must leave a fallback scene, not an empty stack")
    end

    local fine = BaseScene:extend():new()
    SceneManager.switch(fine)
    SceneManager.push(Broken:new())
    equal(SceneManager.current(), fine, "push enter failure reverts to previous scene")
    SceneManager.quit()
end

local function testMath3D()
    local Vec3 = require("engine.math.Vec3")
    local Quat = require("engine.math.Quat")
    local Mat4 = require("engine.math.Mat4")

    local function near(actual, expected, message)
        if math.abs(actual - expected) > 1e-4 then
            error(message .. ": expected " .. expected .. ", got " .. actual)
        end
    end

    -- Vec3
    local c = Vec3.crossTo(Vec3.new(), Vec3.new(1, 0, 0), Vec3.new(0, 1, 0))
    near(c.z, 1, "cross(X,Y) = Z")
    near(Vec3.dot(Vec3.new(1, 2, 3), Vec3.new(4, 5, 6)), 32, "dot product")

    -- Quat：绕 Y 轴 90° 把 +X 转到 -Z
    local q = Quat.fromAxisAngle(Vec3.new(0, 1, 0), math.pi / 2)
    local v = Quat.rotateVec3To(Vec3.new(), q, Vec3.new(1, 0, 0))
    near(v.x, 0, "quat rotate: x")
    near(v.z, -1, "quat rotate: z")

    -- slerp 半程 = 绕 Y 轴 45°
    local h = Quat.slerpTo(Quat.new(), Quat.identity(), q, 0.5)
    local hv = Quat.rotateVec3To(Vec3.new(), h, Vec3.new(1, 0, 0))
    near(hv.x, math.cos(math.pi / 4), "slerp halfway")

    -- Mat4 lookAt：相机在 (0,0,5) 看原点，原点应落在视图空间 -z 轴上
    local view = Mat4.new():setLookAt(Vec3.new(0, 0, 5), Vec3.new(0, 0, 0), Vec3.new(0, 1, 0))
    local x, y, z = view:transformPoint(0, 0, 0)
    near(x, 0, "lookAt x"); near(y, 0, "lookAt y"); near(z, -5, "lookAt z")

    -- 透视投影：near 平面中心映射到 NDC z=-1，far 平面映射到 +1
    local proj = Mat4.new():setPerspective(math.rad(60), 16 / 9, 0.1, 100, false)
    local _, _, zn, wn = proj:transformPoint(0, 0, -0.1)
    near(zn / wn, -1, "perspective maps near plane to -1")
    local _, _, zf, wf = proj:transformPoint(0, 0, -100)
    near(zf / wf, 1, "perspective maps far plane to +1")

    local ortho = Mat4.new():setOrthographic(-10, 10, -5, 5, 1, 101, false)
    local ox, oy, oz, ow = ortho:transformPoint(10, 5, -101)
    near(ox / ow, 1, "orthographic maps right extent to 1")
    near(oy / ow, 1, "orthographic maps top extent to 1")
    near(oz / ow, 1, "orthographic maps far plane to 1")

    -- TRS：平移(1,2,3) + 单位旋转 + 缩放2，作用于 (1,0,0) → (3,2,3)
    local m = Mat4.new():setTRS(Vec3.new(1, 2, 3), Quat.identity(), 2)
    local px, py, pz = m:transformPoint(1, 0, 0)
    near(px, 3, "TRS x"); near(py, 2, "TRS y"); near(pz, 3, "TRS z")

    -- 法线矩阵：非均匀缩放时应使用上三阶逆转置
    local scaled = Mat4.new():setTRS(Vec3.new(0, 0, 0), Quat.identity(), Vec3.new(2, 3, 4))
    local normal = Mat4.new():setNormalFromModel(scaled)
    local nx, ny, nz = normal:transformPoint(1, 1, 1)
    near(nx, 0.5, "normal matrix inverse scale x")
    near(ny, 1 / 3, "normal matrix inverse scale y")
    near(nz, 0.25, "normal matrix inverse scale z")
end

local function testRenderState()
    local RenderState = require("engine.rendering.RenderState")
    RenderState.apply({
        cullMode = "back",
        winding = "cw",
        depthMode = { "lequal", true },
        color = { 0.5, 0.25, 0.125, 0.5 },
    })
    equal(love.graphics.getMeshCullMode(), "back", "render state applies cull mode")
    equal(love.graphics.getFrontFaceWinding(), "cw", "render state applies winding")
    RenderState.reset()
    equal(love.graphics.getMeshCullMode(), "none", "reset restores cull baseline")
    equal(love.graphics.getFrontFaceWinding(), "ccw", "reset restores winding baseline")
    local compare, write = love.graphics.getDepthMode()
    equal(compare, "always", "reset disables depth test")
    equal(write, false, "reset disables depth write")
    local r = love.graphics.getColor()
    equal(r, 1, "reset restores white color")
    equal(love.graphics.getShader(), nil, "reset clears shader")
    equal(love.graphics.getCanvas(), nil, "reset returns to backbuffer")
end

local function testRenderPipeline()
    local ResourceManager = require("engine.managers.ResourceManager")
    local RenderPipeline = require("engine.rendering.RenderPipeline")
    local scope = ResourceManager:createSceneScope("pipeline-test")
    ResourceManager:activateSceneScope(scope)
    ResourceManager:createCanvas(32, 32, nil, "scene", "pipe_a")
    ResourceManager:createCanvas(32, 32, nil, "scene", "pipe_b")

    local log = {}
    local expectedViewport = 32
    local pipeline = RenderPipeline.new("test")
    pipeline:addPass({
        name = "first",
        output = "pipe_a",
        clear = { 0, 0, 0, 1 },
        state = {
            cullMode = "back",
            winding = function(_, pass)
                equal(pass.viewportWidth, expectedViewport, "pass exposes output viewport width before state apply")
                equal(pass.viewportHeight, expectedViewport, "pass exposes output viewport height before state apply")
                return "cw"
            end,
        },
        draw = function(context)
            log[#log + 1] = "first:" .. tostring(context)
            equal(love.graphics.getCanvas() == ResourceManager:get("pipe_a"), true,
                "pass binds its declared output canvas")
            equal(love.graphics.getMeshCullMode(), "back", "pass state spec is applied")
            equal(love.graphics.getFrontFaceWinding(), "cw", "dynamic pass state is applied")
        end,
    })
    pipeline:addPass({
        name = "second",
        input = "pipe_a",
        output = "pipe_b",
        draw = function(_, inputs)
            log[#log + 1] = "second"
            equal(inputs[1] == ResourceManager:get("pipe_a"), true, "pass inputs resolve by name")
            equal(love.graphics.getMeshCullMode(), "none", "state is force-reset between passes")
        end,
    })
    pipeline:execute("ctx")
    equal(table.concat(log, ","), "first:ctx,second", "passes execute in declared order")
    equal(love.graphics.getCanvas(), nil, "execute ends on the backbuffer")
    equal(love.graphics.getMeshCullMode(), "none", "execute restores the 2D baseline")

    -- resetCanvas 重建后，管线按名重解析拿到新对象（resize 红利）
    local oldCanvas = ResourceManager:get("pipe_a")
    ResourceManager:resetCanvas("pipe_a", 16, 16)
    expectedViewport = 16
    local seen
    pipeline:getPass("first").draw = function() end
    pipeline:getPass("second").draw = function(_, inputs) seen = inputs[1] end
    pipeline:execute()
    equal(seen ~= oldCanvas, true, "rebuilt canvas is not the stale reference")
    equal(seen == ResourceManager:get("pipe_a"), true, "pipeline re-resolves rebuilt canvases")

    pipeline:setEnabled("second", false)
    log = {}
    pipeline:getPass("first").draw = function() log[#log + 1] = "first" end
    pipeline:execute()
    equal(table.concat(log, ","), "first", "disabled pass is skipped")

    ResourceManager:releaseSceneScope(scope)
end

local function testObjLoader()
    local ObjLoader = require("engine.rendering.ObjLoader")
    local quad = table.concat({
        "v 0 0 0", "v 1 0 0", "v 1 1 0", "v 0 1 0",
        "vt 0 0", "vt 1 0", "vt 1 1", "vt 0 1",
        "vn 0 0 1",
        "f 1/1/1 2/2/1 3/3/1 4/4/1",
    }, "\n")
    local data = ObjLoader.parse(quad)
    equal(data.vertexCount, 4, "obj quad dedupes shared corners")
    equal(data.indexCount, 6, "obj quad triangulates into two triangles")
    equal(data.indices[4], 1, "fan triangulation reuses the first corner")
    equal(data.vertices[1][5], 1, "obj flips the texture v axis")
    equal(math.abs(data.boundingRadius - math.sqrt(2)) < 1e-6, true,
        "bounding radius measured from model origin")

    local flat = ObjLoader.parse("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n")
    equal(flat.vertices[1][8], 1, "missing vn falls back to computed face normal")
    equal(flat.vertexCount, 3, "face-normal fallback keeps per-face vertices")
end

local function testMeshBinRoundtrip()
    local ObjLoader = require("engine.rendering.ObjLoader")
    local MeshBin = require("engine.rendering.MeshBin")
    local data = ObjLoader.parse(table.concat({
        "v 0 0 0", "v 1 0 0", "v 1 1 0", "v 0 1 0",
        "vt 0 0", "vt 1 0", "vt 1 1", "vt 0 1",
        "vn 0 0 1",
        "f 1/1/1 2/2/1 3/3/1 4/4/1",
    }, "\n"))

    local decoded = MeshBin.decode(MeshBin.encode(data))
    equal(decoded.header.vertexCount, 4, "meshbin roundtrips vertex count")
    equal(decoded.header.indexCount, 6, "meshbin roundtrips index count")
    equal(decoded.header.indexType, "uint16", "small mesh uses uint16 indices")
    equal(decoded.vertexData:getSize(), 4 * 8 * 4, "vertex stream is 8 float32 per vertex")
    equal(love.data.unpack("<f", decoded.vertexData, 4 * 4 + 1), 1,
        "vertex stream preserves flipped v coordinate")
    equal(love.data.unpack("<I2", decoded.indexData, 3 * 2 + 1), 0,
        "index stream is zero-based")

    local mesh = MeshBin.toMesh(decoded)
    equal(mesh:getVertexCount(), 4, "meshbin data feeds newMesh without parsing")
    mesh:release()

    -- tools/obj2mesh.js 的离线产物必须能被同一解码器读取
    if love.filesystem.getInfo("samples/cube3d/assets/models/gem.mesh") then
        local gem = MeshBin.decode(love.filesystem.read("samples/cube3d/assets/models/gem.mesh"))
        equal(gem.header.vertexCount, 24, "node obj2mesh output decodes with MeshBin")
        equal(math.abs(gem.header.boundingRadius - 0.8) < 1e-6, true,
            "node obj2mesh preserves bounding radius")
    end
end

local function testShaderPreprocessor()
    local Pre = require("engine.rendering.ShaderPreprocessor")
    local plain = "vec4 effect() { return vec4(1.0); }"
    equal(Pre.process(plain), plain, "source without includes passes through unchanged")

    local expanded = Pre.process('#include "inc_root.glsl"\nvoid main() {}', "tests/fixtures/shaders")
    local _, sharedCount = expanded:gsub("float sharedValue", "")
    equal(sharedCount, 1, "repeated include expands only once")
    equal(expanded:find("float nestedValue", 1, true) ~= nil, true, "nested includes expand")
    equal(expanded:find("#include", 1, true), nil, "no include directives remain after expansion")

    local viaRoot = Pre.process('#include "tests/fixtures/shaders/inc_shared.glsl"')
    equal(viaRoot:find("sharedValue", 1, true) ~= nil, true, "project-root include path resolves")

    equal(pcall(Pre.process, '#include "does_not_exist.glsl"', "tests/fixtures/shaders"), false,
        "missing include raises")
    local okCycle, message = pcall(Pre.process, '#include "inc_cycle_a.glsl"', "tests/fixtures/shaders")
    equal(okCycle, false, "circular include raises")
    equal(tostring(message):find("circular", 1, true) ~= nil, true, "cycle error explains itself")

    equal(Pre.moduleDir("samples.cube3d.assets.shaders.Basic3D"), "samples/cube3d/assets/shaders",
        "shader module path maps to its include base directory")
end

local function testObjLoaderObjects()
    local ObjLoader = require("engine.rendering.ObjLoader")
    local MeshBin = require("engine.rendering.MeshBin")
    local level = table.concat({
        "mtllib level.mtl", -- Blender 噪声行，必须被容错忽略
        "o room_a",
        "v 0 0 0", "v 1 0 0", "v 1 1 0", "v 0 1 0",
        "usemtl wall",
        "s off",
        "f 1 2 3 4",
        "o room_b",
        "v 4 0 0", "v 5 0 0", "v 5 1 0",
        "usemtl accent",
        "f 5 6 7",
    }, "\n")
    local data = ObjLoader.parse(level)
    equal(#data.objects, 2, "o lines split the object table")
    local a, b = data.objects[1], data.objects[2]
    equal(a.name, "room_a", "object keeps its blender name")
    equal(a.material, "wall", "object keeps usemtl material")
    equal(a.indexStart, 1, "first object starts at index 1")
    equal(a.indexCount, 6, "quad object triangulates to 6 indices")
    equal(b.indexStart, 7, "second object range follows the first")
    equal(b.indexCount, 3, "triangle object has 3 indices")
    equal(math.abs(b.center[1] - 4.5) < 1e-6, true, "object center comes from its own AABB")
    equal(math.abs(b.boundingRadius - math.sqrt(0.5)) < 1e-6, true,
        "object bounding sphere wraps its AABB")

    local decoded = MeshBin.decode(MeshBin.encode(data))
    equal(#decoded.header.objects, 2, "meshbin roundtrips the object table")
    equal(decoded.header.objects[2].name, "room_b", "meshbin keeps object names")
    equal(decoded.header.objects[2].material, "accent", "meshbin keeps object materials")
    equal(decoded.header.objects[2].indexStart, 7, "meshbin keeps draw ranges")
end

local function testLevelMeshObjectDrawing()
    local ObjLoader = require("engine.rendering.ObjLoader")
    local MeshBin = require("engine.rendering.MeshBin")
    local LevelMesh = require("engine.rendering.LevelMesh")
    local Mat4 = require("engine.math.Mat4")

    local data = ObjLoader.parse(table.concat({
        "o near_piece",
        "usemtl wall",
        "v 0 0 0", "v 1 0 0", "v 0 1 0",
        "f 1 2 3",
        "o far_piece",
        "usemtl accent",
        "v 8 0 0", "v 9 0 0", "v 8 1 0",
        "f 4 5 6",
        "o floor_col",
        "usemtl collision",
        "v 0 0 2", "v 1 0 2", "v 0 1 2",
        "f 7 8 9",
        "o door_trigger",
        "usemtl trigger",
        "v 0 0 3", "v 1 0 3", "v 0 1 3",
        "f 10 11 12",
    }, "\n"))
    local decoded = MeshBin.decode(MeshBin.encode(data))
    local materials = LevelMesh.compileMaterials({
        wall = { albedo = "wall_a", normal = "wall_n", pbr = "wall_p", alphaMask = "wall_alpha", roughness = 0.25 },
    }, function(name) return "resolved:" .. name end)
    equal(materials.wall.albedoTexture, "resolved:wall_a", "level material resolves albedo texture")
    equal(materials.wall.normalTexture, "resolved:wall_n", "level material resolves normal texture")
    equal(materials.wall.pbrTexture, "resolved:wall_p", "level material resolves pbr texture")
    equal(materials.wall.alphaMaskTexture, "resolved:wall_alpha", "level material resolves alpha mask texture")
    equal(materials.wall.roughness, 0.25, "level material preserves scalar pbr values")

    local level = LevelMesh.new(MeshBin.toMesh(decoded), decoded.header, {
        wall = { color = { 0.5, 0.5, 0.5, 1 } },
        accent = { color = { 1, 0.5, 0.25, 1 } },
    })
    equal(#level.allObjects, 4, "levelmesh keeps full object table")
    equal(#level.objects, 2, "levelmesh filters non-render suffix objects")
    equal(#level.colliders, 1, "levelmesh exposes collider suffix objects")
    equal(#level.triggers, 1, "levelmesh exposes trigger suffix objects")
    equal(level.colliders[1].name, "floor_col", "collider object name is preserved")

    local stats = { drawn = 0, culled = 0 }
    local drawn = {}
    local camera = {
        isSphereVisible = function(_, x) return x < 4 end,
    }
    level:drawObjects({
        camera = camera,
        model = Mat4.new(),
        stats = stats,
        draw = function(_, object, material)
            drawn[#drawn + 1] = object.name .. ":" .. object.material .. ":" .. tostring(material.color[1])
        end,
    })

    equal(stats.drawn, 1, "levelmesh draws visible object ranges")
    equal(stats.culled, 1, "levelmesh culls invisible object ranges")
    equal(drawn[1], "near_piece:wall:0.5", "levelmesh binds object material")
    level:release()
end

local function testCamera3DFrustum()
    local Camera3D = require("engine.rendering.Camera3D")
    local cam = Camera3D.new()
    cam:setPerspective(math.rad(60), 16 / 9, 0.1, 100) -- 显式 aspect，不依赖 love 窗口
    cam:setPosition(0, 0, 10)
    cam:lookAt(0, 0, 0)
    equal(cam:isPointVisible(0, 0, 0), true, "look target is visible")
    equal(cam:isPointVisible(0, 0, 20), false, "point behind camera is culled")
    equal(cam:isPointVisible(0, 0, -200), false, "point beyond far plane is culled")
    equal(cam:isSphereVisible(0, 100, 0, 1), false, "sphere far above frustum is culled")
    equal(cam:isSphereVisible(0, 0, -95, 10), true, "sphere straddling far plane is kept")

    cam:setPerspective(math.rad(60), nil, 0.1, 100)
    cam:resize(200, 100)
    local wide = cam:getProjection()
    equal(math.abs(math.abs(wide[6]) * 0.5 - wide[1]) < 1e-6, true,
        "camera projection follows explicit viewport aspect")
end

local function testStrategyCameraBounds()
    local StrategyCamera = require("engine.rendering.StrategyCamera")
    local camera = {
        position = {},
        target = {},
        setPosition = function(self, x, y, z)
            self.position.x, self.position.y, self.position.z = x, y, z
        end,
        lookAt = function(self, x, y, z)
            self.target.x, self.target.y, self.target.z = x, y, z
        end,
    }
    local controller = StrategyCamera.new(camera, {
        yaw = 0,
        pitch = 0,
        distance = 50,
        minDistance = 1,
        maxDistance = 50,
        minPitch = 0,
        maxPitch = math.rad(80),
        minEyeHeight = 0,
        maxEyeHeight = 100,
        edgePadding = 1,
        targetBounds = { minX = -5, maxX = 5, minZ = -5, maxZ = 5 },
        eyeBounds = { minX = -10, maxX = 10, minZ = -10, maxZ = 10 },
    })

    controller:setTarget(20, 0, 0):update()
    equal(controller.target.x, 5, "strategy camera clamps the look target to the playable area")
    equal(math.abs(controller.effectiveDistance - 4) < 1e-6, true,
        "strategy camera shortens zoom at the eye boundary")
    equal(math.abs(camera.position.x - 9) < 1e-6, true,
        "strategy camera keeps the eye inside its boundary")
end

local function testNagashinoBattleEvents()
    local BattleSimulation = require("games.nagashino.gameplay.BattleSimulation")
    local simulation = BattleSimulation.new()
    simulation:update(2.5)
    local muzzleCount, impactCount = 0, 0
    for _, event in ipairs(simulation:drainEvents()) do
        if event.type == "muzzle" then muzzleCount = muzzleCount + 1 end
        if event.type == "impact" then impactCount = impactCount + 1 end
    end
    equal(muzzleCount > 0, true, "three-rank volley emits muzzle events")
    equal(impactCount > 0, true, "volley emits irregular ground-impact events")

    local casualty = simulation.units[#simulation.units]
    simulation:kill(casualty)
    simulation:update(0.70) -- > DEATH_FALL_DURATION：倒地动画播完才落地生成尸体效果
    local events = simulation:drainEvents()

    -- 倒地三件套是"同一个单位、连续三条、固定顺序"，但同一次 update 里齐射
    -- （emitVolleyEffects 在单位循环之前跑）可能先塞进 muzzle/impact——
    -- 所以按 blood 的位置锚定，而不是假设它们从 events[1] 开始。
    -- 与齐射事件的先后无人依赖：BattleEffects 是按 type 分发的平坦循环。
    local bloodIndex
    for index, event in ipairs(events) do
        if event.type == "blood" then
            bloodIndex = index
            break
        end
    end
    equal(bloodIndex ~= nil, true, "casualties emit persistent blood-stain events")
    equal(events[bloodIndex + 1].type, "casualty", "casualties emit fallen-sprite events")
    equal(events[bloodIndex + 1].role, "cavalry", "fallen-sprite event preserves unit role")
    equal(events[bloodIndex + 2].type, "weapon", "casualties emit dropped-weapon events")
end

local function testNagashinoDustEffects()
    local BattleEffects = require("games.nagashino.rendering.BattleEffects")
    local BattleSimulation = require("games.nagashino.gameplay.BattleSimulation")
    local function particleSink()
        return {
            emitted = 0,
            emitBurst = function(self) self.emitted = self.emitted + 1 end,
            update = function() end,
            clear = function() end,
        }
    end
    local dust = particleSink()
    local craterCount = 0
    local effects = BattleEffects.new(particleSink(), dust, {
        queue = function() end,
        queueBlood = function() end,
        queueCorpse = function() end,
        queueCrater = function() craterCount = craterCount + 1 end,
    })
    local simulation = BattleSimulation.new()
    for _ = 1, 390 do
        simulation:update(1 / 60)
        effects:update(simulation, 1 / 60)
    end
    equal(dust.emitted > 0, true, "Takeda charge emits horse and formation dust")
    equal(effects.dustEmitted > 0, true, "dust diagnostics count emitted bursts")
    equal(craterCount > 0, true, "musket impacts queue persistent ground craters")
end

function Tests.run()
    local cases = {
        testEventBus,
        testTimestep,
        testInputMap,
        testInputRecorder,
        testSceneInstances,
        testSceneResourceScopes,
        testSceneInputDispatch,
        testObjectInheritance,
        testMath3D,
        testCamera3DFrustum,
        testStrategyCameraBounds,
        testNagashinoBattleEvents,
        testNagashinoDustEffects,
        testRenderState,
        testRenderPipeline,
        testObjLoader,
        testMeshBinRoundtrip,
        testShaderPreprocessor,
        testObjLoaderObjects,
        testLevelMeshObjectDrawing,
        testBaseSceneLayerHelpers,
        testSceneSubscriptionCleanup,
        testSceneEnterFailure,
        testTransitionScene,
        testManifestShaderModules,
        testNagashinoManifestAssets,
        testResourceManagerAsyncManifestAndLookup,
        testManifestValidation,
        testInventoryLifecycle,
        testEngineGameBoundary,
        testEngineShaderBoundary,
        testDiagnosticsRegistry,
        testServiceRegistry,
        testSaveService,
        testLLMGameBoundary,
        testLLMCancelStopsWorker,
        testPlayerController,
        testFurniturePoseSystem,
        testInteractionSystem,
        testPlacementSystem,
        testItemWorldSystem,
        testPlayerMonologue,
        testHUDMessages,
        testGameClockAndRest,
        testReadingSystem,
        testComputerOS,
        testEvidenceLog,
        testComputerOSViews,
        testTimedIntercepts,
        testCharacterProfiles,
        testApartmentRendererHistoryPolicy,
        testTinyPhysicsIntegration,
        testTinyPhysicsCleanupIntegration,
    }
    for i, test in ipairs(cases) do
        test()
        print(string.format("[test] %d/%d passed", i, #cases))
    end
    print("[test] all tests passed")
end

return Tests
