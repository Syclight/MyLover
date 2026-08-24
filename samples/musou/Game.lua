local Scene = require("samples.musou.scenes.MusouScene")
local Game = { id = "musou", name = "Musou Sample" }
function Game:createInitialScene() return Scene:new() end
return Game
