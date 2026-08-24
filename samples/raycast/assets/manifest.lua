-- Raycast sample-owned resources.
return {
    images = {
        { path = "samples/raycast/assets/images/statue.png", name = "statue", needData = true },
        { path = "samples/raycast/assets/images/frame_albedo.png", name = "painting_frame_albedo" },
        { path = "samples/raycast/assets/images/frame_normal.png", name = "painting_frame_normal" },
    },
    shaders = {
        { path = "samples/raycast/assets/shaders/RaycastGbuffer.glsl", name = "gbuffer_shader" },
        { path = "samples/raycast/assets/shaders/RaycastGlobalShadow.glsl", name = "shadow_shader" },
        { path = "samples/raycast/assets/shaders/SpriteGBuffer.glsl", name = "sprite_shader" },
        { path = "samples/raycast/assets/shaders/PaintingShader.glsl", name = "painting_shader" },
        { module = "samples.raycast.assets.shaders.AntiAliasShader", name = "raycast_fxaa_shader" },
    },
    canvases = {
        { name = "gAlbedo" },
        { name = "gNormal" },
        { name = "gFinalComposite" },
        { name = "gDepth", settings = { format = "r16f" } }, -- 如果当前显卡不支持 r16f 会自动回退
        { name = "raycast_fxaa_canvas" },
    },
    json = {
        { path = "samples/raycast/assets/maps/level_1.json", name = "level_1" },
    },
    music = {
        { path = "samples/raycast/assets/music/level1_bgm.wav", name = "bgm_ambient" },
    },
    sounds = {
        { path = "samples/raycast/assets/sounds/footsteps_concrete_3_l.wav", name = "footsteps_concrete" },
    },
}
