return {
    images = {
        {
            path = "samples/cube3d/assets/images/container.jpg",
            name = "cube3d_texture",
            -- 3D 贴图三件套：mipmaps 防远处闪烁，anisotropy 保斜视角清晰
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "samples/cube3d/assets/images/flat_normal.png",
            name = "cube3d_normal_flat",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 4 },
        },
        {
            path = "samples/cube3d/assets/images/neutral_pbr.png",
            name = "cube3d_pbr_neutral",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 4 },
        },
    },
    shaders = {
        { module = "samples.cube3d.assets.shaders.Basic3D", name = "cube3d_shader" },
    },
    canvases = {
        -- 不传宽高 = 跟随屏幕分辨率（resize 时 resetAllCanvases 会自动重建）
        { name = "cube3d_canvas" },
    },
}
