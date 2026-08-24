local Scene = require("samples.shader_maze.scenes.ShaderMazeScene")
local Game = { id = "shader_maze", name = "Shader Maze Sample" }
function Game:createInitialScene() return Scene:new() end
return Game
