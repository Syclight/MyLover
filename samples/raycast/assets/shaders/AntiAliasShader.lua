
local FAXX_Shader_v1 = [[
    // 屏幕的宽高倒数，用于获取相邻像素
    extern vec2 texelSize; 
    
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        // 采集当前像素
        vec4 center = Texel(texture, texture_coords);
        
        // 采集上下左右四个相邻像素
        vec4 up    = Texel(texture, texture_coords + vec2(0.0, -texelSize.y));
        vec4 down  = Texel(texture, texture_coords + vec2(0.0, texelSize.y));
        vec4 left  = Texel(texture, texture_coords + vec2(-texelSize.x, 0.0));
        vec4 right = Texel(texture, texture_coords + vec2(texelSize.x, 0.0));
        
        // 极其简易的 FXAA 思想：
        // 如果周围颜色差异很大（说明是边缘），就把它们混合一下
        // 如果颜色差不多，就保持原样
        
        vec4 blurred = (center + up + down + left + right) / 5.0;
        
        // 计算当前像素和周围平均值的色差
        float diff = length(center.rgb - blurred.rgb);
        
        // 设定一个阈值，只有边缘才进行混合抗锯齿
        if (diff > 0.1) {
            return blurred * color;
        } else {
            return center * color;
        }
    }
]]

-- FXAA shader source
-- 这是一个简化版的 FXAA 着色器，专为复古游戏优化

local FAXX_Shader_v2 = [[
    extern vec2 texelSize; // 屏幕一个像素的宽和高 (1/w, 1/h)

    // 计算颜色的亮度
    float luma(vec3 color) {
        return dot(color, vec3(0.299, 0.587, 0.114));
    }

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec2 rcpFrame = texelSize;
        
        // 采样中心点和四周的像素亮度
        vec3 rgbM = Texel(texture, texture_coords).rgb;
        vec3 rgbNW = Texel(texture, texture_coords + vec2(-rcpFrame.x, -rcpFrame.y)).rgb;
        vec3 rgbNE = Texel(texture, texture_coords + vec2(rcpFrame.x, -rcpFrame.y)).rgb;
        vec3 rgbSW = Texel(texture, texture_coords + vec2(-rcpFrame.x, rcpFrame.y)).rgb;
        vec3 rgbSE = Texel(texture, texture_coords + vec2(rcpFrame.x, rcpFrame.y)).rgb;

        float lumaM  = luma(rgbM);
        float lumaNW = luma(rgbNW);
        float lumaNE = luma(rgbNE);
        float lumaSW = luma(rgbSW);
        float lumaSE = luma(rgbSE);

        // 计算亮度的最大最小值，确定边缘对比度
        float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
        float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
        
        // 如果对比度太低，说明不是边缘，直接返回原色
        if (lumaMax - lumaMin < 0.05) {
            return vec4(rgbM, 1.0) * color;
        }

        // 计算混合方向
        vec2 dir;
        dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
        dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

        float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * 0.125), 0.008);
        float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
        dir = min(vec2(8.0, 8.0), max(vec2(-8.0, -8.0), dir * rcpDirMin)) * rcpFrame;

        // 执行两次采样并混合，平滑边缘
        vec3 rgbA = 0.5 * (
            Texel(texture, texture_coords + dir * (1.0 / 3.0 - 0.5)).rgb +
            Texel(texture, texture_coords + dir * (2.0 / 3.0 - 0.5)).rgb);
        vec3 rgbB = rgbA * 0.5 + 0.25 * (
            Texel(texture, texture_coords + dir * -0.5).rgb +
            Texel(texture, texture_coords + dir * 0.5).rgb);
        
        float lumaB = luma(rgbB);
        if ((lumaB < lumaMin) || (lumaB > lumaMax)) {
            return vec4(rgbA, 1.0) * color;
        } else {
            return vec4(rgbB, 1.0) * color;
        }
    }
]]

return FAXX_Shader_v2
