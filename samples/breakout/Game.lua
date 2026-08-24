local BreakoutScene = require("samples.breakout.scenes.BreakoutScene")

local Game = { id = "breakout", name = "Breakout Sample" }

function Game:createInitialScene()
    return BreakoutScene:new()
end

return Game
