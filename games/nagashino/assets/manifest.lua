local manifest = {
    images = {
        {
            path = "games/nagashino/assets/images/grass.png",
            name = "nagashino_grass",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/mud.png",
            name = "nagashino_mud",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/wood.png",
            name = "nagashino_wood",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/water.png",
            name = "nagashino_water",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/foliage.png",
            name = "nagashino_foliage",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "games/nagashino/assets/images/hill.png",
            name = "nagashino_hill",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/smoke.png",
            name = "nagashino_smoke",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "games/nagashino/assets/images/cloth_takeda.png",
            name = "nagashino_cloth_takeda",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "games/nagashino/assets/images/cloth_oda.png",
            name = "nagashino_cloth_oda",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "games/nagashino/assets/images/cloth_tokugawa.png",
            name = "nagashino_cloth_tokugawa",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4 },
        },
        {
            path = "games/nagashino/assets/images/grass_cc0_color.jpg",
            name = "nagashino_grass_cc0_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/grass_cc0_normal.jpg",
            name = "nagashino_grass_cc0_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/grass_cc0_roughness.jpg",
            name = "nagashino_grass_cc0_roughness",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/grass_cc0_ao.jpg",
            name = "nagashino_grass_cc0_ao",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/mud_cc0_color.jpg",
            name = "nagashino_mud_cc0_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/mud_cc0_normal.jpg",
            name = "nagashino_mud_cc0_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/mud_cc0_roughness.jpg",
            name = "nagashino_mud_cc0_roughness",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/mud_cc0_ao.jpg",
            name = "nagashino_mud_cc0_ao",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/rock_cc0_color.jpg",
            name = "nagashino_rock_cc0_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/rock_cc0_normal.jpg",
            name = "nagashino_rock_cc0_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/rock_cc0_roughness.jpg",
            name = "nagashino_rock_cc0_roughness",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/rock_cc0_ao.jpg",
            name = "nagashino_rock_cc0_ao",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/sky_day_cc0.jpg",
            name = "nagashino_sky_day_cc0",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = { "repeat", "clamp" } },
        },
        {
            path = "games/nagashino/assets/images/water_normal.png",
            name = "nagashino_water_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/tree_bark_color.jpg",
            name = "nagashino_tree_bark_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/tree_bark_normal.jpg",
            name = "nagashino_tree_bark_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/tree_leaves_color.jpg",
            name = "nagashino_tree_leaves_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/tree_leaves_normal.jpg",
            name = "nagashino_tree_leaves_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/tree_leaves_alpha.png",
            name = "nagashino_tree_leaves_alpha",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/leaves_color.png",
            name = "nagashino_leaves_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/leaves_normal.png",
            name = "nagashino_leaves_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/flat_normal.png",
            name = "nagashino_flat_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/neutral_pbr.png",
            name = "nagashino_neutral_pbr",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 4, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/ashigaru_hd2d.png",
            name = "nagashino_ashigaru_hd2d",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/takeda_cavalry_sheet.png",
            name = "nagashino_takeda_cavalry_sheet",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/takeda_cavalry_death_sheet.png",
            name = "nagashino_takeda_cavalry_death_sheet",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/alliance_ashigaru_sheet.png",
            name = "nagashino_alliance_ashigaru_sheet",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/alliance_teppo_sheet.png",
            name = "nagashino_alliance_teppo_sheet",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/fallen_casualties_sheet.png",
            name = "nagashino_fallen_casualties_sheet",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/fallen_casualties_edge.png",
            name = "nagashino_fallen_casualties_edge",
            settings = { mipmaps = true, filter = "linear", anisotropy = 4, wrap = "clamp" },
        },
        {
            path = "games/nagashino/assets/images/crater_dirt_color.png",
            name = "nagashino_crater_dirt_color",
            settings = { mipmaps = true, filter = "linear", anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/crater_dirt_normal.png",
            name = "nagashino_crater_dirt_normal",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
        {
            path = "games/nagashino/assets/images/crater_dirt_roughness.jpg",
            name = "nagashino_crater_dirt_roughness",
            settings = { mipmaps = true, filter = "linear", linear = true, anisotropy = 8, wrap = "repeat" },
        },
    },
    shaders = {
        { module = "games.nagashino.assets.shaders.Battlefield3D", name = "nagashino_shader" },
        { module = "games.nagashino.assets.shaders.ShadowDepth", name = "nagashino_shadow_shader" },
        { module = "games.nagashino.assets.shaders.CrowdSprite", name = "nagashino_crowd_sprite_shader" },
        { module = "games.nagashino.assets.shaders.CrowdShadow", name = "nagashino_crowd_shadow_shader" },
        { module = "games.nagashino.assets.shaders.FallenSprite", name = "nagashino_fallen_sprite_shader" },
        { module = "games.nagashino.assets.shaders.Corpse3D", name = "nagashino_corpse3d_shader" },
        { module = "games.nagashino.assets.shaders.DroppedWeapon", name = "nagashino_dropped_weapon_shader" },
        { module = "engine.assets.shaders.CraterDecal", name = "engine_crater_decal_shader" },
        { module = "engine.assets.shaders.Particle3D", name = "engine_particle3d_shader" },
    },
    canvases = {
        { name = "nagashino_canvas" },
        { name = "nagashino_shadow_map", width = 768, height = 768, settings = { format = "r16f" } },
        { name = "nagashino_battlefield_state", width = 768, height = 512 },
    },
}

return manifest
