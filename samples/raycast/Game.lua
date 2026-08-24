local Scene = require("samples.raycast.scenes.RaycastScene")
local Game = { id = "raycast", name = "Raycast Sample" }
function Game:createInitialScene() return Scene:new() end
return Game
