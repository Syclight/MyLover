return {
    shaders = {
        { path = "samples/shader_maze/assets/shaders/ShaderMaze.glsl", name = "shader_maze_shader" },
        { path = "engine/assets/shaders/TemporalUpscale.glsl", name = "shader_maze_taau_shader" },
        { path = "engine/assets/shaders/AntiAlias.glsl", name = "shader_maze_aa_shader" },
    },
    canvases = {
        { name = "shader_maze_canvas", width = 640, height = 360 },
        { name = "shader_maze_history_a" },
        { name = "shader_maze_history_b" },
        { name = "shader_maze_present" },
    },
    binary = {
        { path = "samples/shader_maze/assets/maps/shader_maze_1.smap", name = "shader_maze_level_1_bin" },
    },
}
