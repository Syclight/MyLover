local ResourceManager = require("engine.managers.ResourceManager")
local SceneManager = require("engine.managers.SceneManager")
local FrameLimiter = require("engine.utils.FrameLimiter")
local Timestep = require("engine.utils.Timestep")
local Diagnostics = require("engine.Diagnostics")
local ServiceRegistry = require("engine.services.ServiceRegistry")
local SaveService = require("engine.services.SaveService")

local Engine = {}

local function assertGameContract(game)
    assert(type(game) == "table", "Engine project must provide a game module")
    assert(type(game.id) == "string" and game.id ~= "", "Game.id is required")
    assert(type(game.createInitialScene) == "function", "Game:createInitialScene(context) is required")
end

local function wantsTests(gameArgs)
    if os.getenv("LOVE_RUN_TESTS") == "1" then return true end
    for _, value in ipairs(gameArgs or {}) do
        if value == "--test" then return true end
    end
    return false
end

local function runTests(testModule)
    assert(type(testModule) == "string" and testModule ~= "",
        "project.testModule is required when tests are requested")
    local ok, err = xpcall(function() require(testModule).run() end, debug.traceback)
    if love.graphics then
        pcall(function() require("engine.rendering.RenderState").reset() end)
    end
    local reportPath = os.getenv("LOVE_TEST_REPORT")
    if reportPath then
        local report = io.open(reportPath, "w")
        if report then
            report:write(ok and "PASS\n" or ("FAIL\n" .. tostring(err) .. "\n"))
            report:close()
        end
    end
    love.event.quit(ok and 0 or 1)
end

function Engine.install(project)
    assert(type(project) == "table", "project.lua must return a project definition")
    assert(type(project.game) == "string", "project.game must be a module path")

    local game = require(project.game)
    assertGameContract(game)

    local services = ServiceRegistry.new()
    local saves = SaveService.new(project.save or {})
    local context = {
        scenes = SceneManager,
        resources = ResourceManager,
        project = project,
        game = game,
        diagnostics = Diagnostics,
        services = services,
        saves = saves,
    }
    local debugOverlay
    local smokeReportPath = os.getenv("LOVE_SMOKE_REPORT")
    local smokeFinished = false

    function love.load(gameArgs)
        if not project.release and wantsTests(gameArgs) then
            runTests(project.testModule)
            return
        end

        if project.globalManifest then
            ResourceManager:loadManifest(project.globalManifest, "global")
        end
        -- Keep the debug UI out of the require graph for release packages.  The
        -- packager can then omit DebugLayer.lua (and its profiling helpers)
        -- instead of merely hiding the overlay at runtime.
        if project.debugOverlay ~= false then
            debugOverlay = require("engine.layers.DebugLayer").new()
        end
        if game.start then game:start(context, gameArgs) end
        services:startAll(context)
        SceneManager.switch(game:createInitialScene(context, gameArgs))
    end

    function love.update(dt) SceneManager.update(dt) end

    function love.frameupdate(dt)
        services:update(dt)
        if debugOverlay then debugOverlay:update(dt) end
        if game.frameupdate then game:frameupdate(context, dt) end
    end

    function love.draw()
        SceneManager.draw()
        if debugOverlay then debugOverlay:draw() end
        if smokeReportPath and not smokeFinished then
            smokeFinished = true
            local report = io.open(smokeReportPath, "w")
            if report then report:write("PASS\n"); report:close() end
            love.event.quit(0)
        end
    end

    -- 事件参数必须全量转发：scancode/isrepeat 是 InputMap 按 scancode 绑定与
    -- 重复键过滤的依据，istouch/presses 是触屏与多击检测的依据，丢了就再也拿不到。
    function love.keypressed(key, scancode, isrepeat)
        if debugOverlay and debugOverlay:keypressed(key) then return end
        SceneManager.keypressed(key, scancode, isrepeat)
    end

    function love.textinput(text) SceneManager.textinput(text) end
    function love.textedited(text, start, length) SceneManager.textedited(text, start, length) end
    function love.mousepressed(...) SceneManager.mousepressed(...) end
    function love.mousereleased(...) SceneManager.mousereleased(...) end
    function love.keyreleased(...) SceneManager.keyreleased(...) end
    function love.mousemoved(...) SceneManager.mousemoved(...) end
    function love.wheelmoved(x, y) SceneManager.wheelmoved(x, y) end
    function love.resize(...) SceneManager.resize(...) end
    function love.focus(...) SceneManager.focus(...) end
    function love.visible(...) SceneManager.visible(...) end
    function love.gamepadpressed(...) SceneManager.gamepadpressed(...) end
    function love.gamepadreleased(...) SceneManager.gamepadreleased(...) end
    function love.joystickpressed(...) SceneManager.joystickpressed(...) end
    function love.joystickreleased(...) SceneManager.joystickreleased(...) end
    function love.touchpressed(...) SceneManager.touchpressed(...) end
    function love.touchreleased(...) SceneManager.touchreleased(...) end
    function love.touchmoved(...) SceneManager.touchmoved(...) end

    function love.quit()
        SceneManager.quit()
        services:stopAll()
        if game.stop then game:stop(context) end
        Diagnostics.clear()
        ResourceManager:unloadAll()
    end

    function love.run()
        if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
        if love.timer then love.timer.step() end

        local function stepSimulation(fixedDt)
            if love.update then love.update(fixedDt) end
        end
        local dt = 0

        return function()
            local frameStart = love.timer and love.timer.getTime() or 0
            if love.event then
                love.event.pump()
                for name, a, b, c, d, e, f in love.event.poll() do
                    if name == "quit" and (not love.quit or not love.quit()) then return a or 0 end
                    love.handlers[name](a, b, c, d, e, f)
                end
            end

            if love.timer then dt = love.timer.step() end
            Timestep:advance(dt, stepSimulation)
            if love.frameupdate then love.frameupdate(dt) end

            if love.graphics and love.graphics.isActive() then
                love.graphics.origin()
                love.graphics.clear(love.graphics.getBackgroundColor())
                if love.draw then love.draw() end
                love.graphics.present()
            end

            if love.timer then
                if FrameLimiter:isLimited() then FrameLimiter:wait(frameStart)
                else love.timer.sleep(0.001) end
            end
        end
    end

    return context
end

return Engine
