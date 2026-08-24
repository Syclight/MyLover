-- Surveillance 游戏专属资源；后处理 Shader 仍复用引擎共享资源。
-- 公寓光投场景资源：复用 ShaderMaze 的三个着色器文件（不改文件，仅以新资源名加载）
-- + 同规格四 canvas + 公寓二进制地图。
return {
    images = {
        { path = "games/surveillance/assets/images/apartment_material_atlas.png", name = "apt_material_atlas" },
    },
    shaders = {
        { path = "games/surveillance/assets/shaders/Apartment.glsl", name = "apt_shader" },
        { path = "engine/assets/shaders/TemporalUpscale.glsl", name = "apt_taau" },
        { path = "games/surveillance/assets/shaders/ApartmentPresent.glsl", name = "apt_aa" },
    },
    canvases = {
        { name = "apt_canvas", width = 640, height = 360 },
        { name = "apt_history_a" }, -- 默认屏幕分辨率
        { name = "apt_history_b" },
        { name = "apt_present" },
        { name = "apt_calendar_texture", width = 512, height = 640 },
    },
    binary = {
        { path = "games/surveillance/assets/maps/apartment_1.smap", name = "apt_level_bin" },
    },
}
