io.stdout:setvbuf("no")

local startupReport = os.getenv("LOVE_TEST_REPORT")
if startupReport then
    function love.errorhandler(message)
        local trace = debug.traceback("LÖVE startup error: " .. tostring(message), 2)
        local report = io.open(startupReport, "w")
        if report then report:write("FAIL\n", trace, "\n"); report:close() end
        return function() return 1 end
    end
end

require("engine.Engine").install(require("project"))
