extern vec3 u_normal;
extern float u_depth;
extern bool u_isFloor;
extern float u_screenHeight;
extern float u_zPlayer;
extern float u_maxDepth;

void effect() {
    // 【修复这里】：使用 VaryingColor 来获取 love.graphics.setColor() 的颜色
    vec4 albedo = VaryingColor; 
    vec3 norm = u_normal;
    float depth = u_depth;

    // 【核心魔法】：我们在 GPU 里实时计算像素级的地板深度！
    if (u_isFloor) {
        norm = vec3(0.0, 0.0, 1.0); // 地板法线永远朝上 (Z轴正向)
        float p = love_PixelCoord.y - (u_screenHeight / 2.0);
        if (p > 0.0) {
            depth = (u_zPlayer * u_screenHeight) / p;
        } else {
            depth = u_maxDepth;
        }
    }

    // 将法线从 [-1, 1] 映射到 [0, 1]，以便存入彩色画布
    vec3 encodedNormal = norm * 0.5 + 0.5;
    // 将深度限制在 0~1 之间
    float encodedDepth = clamp(depth / u_maxDepth, 0.0, 1.0);

    // 输出到三个渲染目标 (MRT)
    love_Canvases[0] = albedo;
    love_Canvases[1] = vec4(encodedNormal, 1.0);
    love_Canvases[2] = vec4(encodedDepth, encodedDepth, encodedDepth, 1.0);
}