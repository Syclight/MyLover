-- 这是一个简单的 GLSL 着色器，包含：
-- 1. 简单的正弦波扭曲 (Wobble)
-- 2. 红色警报叠加 (Red Overlay)
-- 3. 边缘暗角 (Vignette - 恐怖游戏标配)

return [[
    extern number time;            // 游戏运行时间 (用于动画)
    extern number distortion;      // 扭曲强度 (0 ~ 1)
    extern number red_strength;    // 红色强度 (0 ~ 1)
    
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        // --- 1. 扭曲效果 (Distortion) ---
        // 利用 sin 函数偏移纹理坐标
        vec2 coord = texture_coords;
        coord.x += sin(coord.y * 50.0 + time * 10.0) * (0.005 * distortion);
        coord.y += cos(coord.x * 50.0 + time * 10.0) * (0.005 * distortion);
        
        // 获取像素颜色
        vec4 pixel = Texel(texture, coord);
        
        // --- 2. 红色蒙版 (Red Mask) ---
        // 简单的线性混合：原色 + 红色
        // 恐怖游戏常用：让红色通道过曝
        pixel.r = pixel.r + red_strength;
        pixel.g = pixel.g - (red_strength * 0.5); // 稍微降低绿
        pixel.b = pixel.b - (red_strength * 0.5); // 稍微降低蓝
        
        // --- 3. 暗角 (Vignette) ---
        // 计算当前像素距离屏幕中心的距离
        vec2 uv = screen_coords / love_ScreenSize.xy;
        vec2 center = vec2(0.5, 0.5);
        float dist = distance(uv, center);
        
        // 距离越远越黑 (暗角强度也可以做成变量)
        float vignette = 1.0 - (dist * 0.8 * red_strength); 
        pixel.rgb *= vignette;

        return pixel * color;
    }
]]