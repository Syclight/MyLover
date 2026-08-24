local Scene = require("games.nagashino.scenes.NagashinoScene")

local Game = { id = "nagashino", name = "Nagashino: Shitaragahara" }

function Game:createInitialScene()
    return Scene:new()
end

return Game
