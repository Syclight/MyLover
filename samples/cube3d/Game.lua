local Scene = require("samples.cube3d.scenes.Cube3DScene")
local Game = { id = "cube3d", name = "Cube3D Sample (P0 3D milestone)" }
function Game:createInitialScene() return Scene:new() end
return Game
