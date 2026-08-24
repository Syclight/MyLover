// // 接收各种贴图
// uniform sampler2D u_paintingTex; // 画心 (比如基里科的画作)
// uniform sampler2D u_frameTex;    // 画框颜色 (九宫格)
// uniform sampler2D u_frameNormal; // 画框法线 (九宫格)

// uniform vec2 u_size;             // 画作在墙上的物理尺寸 (宽, 高)
// uniform float u_frameThickness;  // 画框边缘的物理厚度 (例如 0.05米)

// uniform vec3 u_baseNormal;       // 墙壁的基础法线
// uniform float u_depth;           // 深度 (加入偏移量后的)
// uniform float u_maxDepth;        // 最大可视深度
// uniform float u_currentU;        // 【核心】Lua 传来的当前列的横向 UV (0.0~1.0)

// void effect() {
//     // 1. 构建当前像素在这幅画上的绝对 UV
//     // VaryingTexCoord.y 是垂直方向的进度 (0~1)，u_currentU 是水平进度
//     vec2 uv = vec2(u_currentU, VaryingTexCoord.y);
    
//     // 计算边框的 UV 占比阈值
//     float tx = u_frameThickness / u_size.x;
//     float ty = u_frameThickness / u_size.y;
    
//     vec4 albedo = vec4(0.0);
//     vec3 localNormal = vec3(0.0, 0.0, 1.0); // 默认法线朝向正前方
    
//     // 2. 九宫格区域判定
//     bool isFrameX = (uv.x < tx) || (uv.x > 1.0 - tx);
//     bool isFrameY = (uv.y < ty) || (uv.y > 1.0 - ty);
    
//     if (isFrameX || isFrameY) {
//         // --- 渲染画框 ---
//         vec2 frameUV = uv;

//         // X轴九宫格映射 (适配你 15% 边框宽度的贴图)
//         if (uv.x < tx) { frameUV.x = uv.x / tx * 0.15; }
//         else if (uv.x > 1.0 - tx) { frameUV.x = 0.85 + (uv.x - (1.0 - tx)) / tx * 0.15; }
//         else { frameUV.x = 0.15 + (uv.x - tx) / (1.0 - 2.0 * tx) * 0.70; }
        
//         // Y轴九宫格映射
//         if (uv.y < ty) { frameUV.y = uv.y / ty * 0.15; }
//         else if (uv.y > 1.0 - ty) { frameUV.y = 0.85 + (uv.y - (1.0 - ty)) / ty * 0.15; }
//         else { frameUV.y = 0.15 + (uv.y - ty) / (1.0 - 2.0 * ty) * 0.70; }
        
//         albedo = Texel(u_frameTex, frameUV);
        
//         // 采样并解压法线贴图 (RGB -> XYZ)
//         vec3 sampledNormal = Texel(u_frameNormal, frameUV).xyz;
//         localNormal = normalize(sampledNormal * 2.0 - 1.0);
//     } else {
//         // --- 渲染画心 ---
//         // 将中心区域的 UV 重新映射到 0~1，用于完整显示画作
//         vec2 paintingUV = vec2(
//             (uv.x - tx) / (1.0 - 2.0 * tx),
//             (uv.y - ty) / (1.0 - 2.0 * ty)
//         );
//         albedo = Texel(u_paintingTex, paintingUV);
//         // 画心是平坦的
//         localNormal = vec3(0.0, 0.0, 1.0);
//     }
    
//     // 3. 切线空间(Tangent Space)转换 (TBN 矩阵)
//     // 根据墙壁朝向动态构建局部坐标系，确保光影总是正确的
//     vec3 N = normalize(u_baseNormal);
//     vec3 T = vec3(0.0);
//     if (abs(N.x) > 0.5) { T = vec3(0.0, -sign(N.x), 0.0); } 
//     else { T = vec3(sign(N.y), 0.0, 0.0); }
//     vec3 B = vec3(0.0, 0.0, -1.0); // 引擎中 Z 轴向上，纹理 Y 轴向下
    
//     vec3 worldNormal = normalize(T * localNormal.x + B * localNormal.y + N * localNormal.z);
    
//     // 4. 写入 G-Buffer (颜色，法线，深度)
//     love_Canvases[0] = albedo;
//     love_Canvases[1] = vec4(worldNormal * 0.5 + 0.5, 1.0);
//     love_Canvases[2] = vec4(u_depth / u_maxDepth, 0.0, 0.0, 1.0);
// }

uniform sampler2D u_paintingTex; 
uniform sampler2D u_frameTex;    
uniform sampler2D u_frameNormal; 

uniform vec2 u_size;             
uniform float u_frameThickness;  

uniform vec3 u_baseNormal;       
uniform float u_depth;           
uniform float u_maxDepth;        
uniform float u_currentU;        

// 【新增】：接收从 Lua 传过来的玩家视线方向
uniform vec3 u_viewDir;          

void effect() {
    vec2 uv = vec2(u_currentU, VaryingTexCoord.y);
    
    float tx = u_frameThickness / u_size.x;
    float ty = u_frameThickness / u_size.y;
    
    vec4 albedo = vec4(0.0);
    vec3 localNormal = vec3(0.0, 0.0, 1.0); 
    
    // 构建切线空间矩阵 (用于法线和视差)
    vec3 N = normalize(u_baseNormal);
    vec3 T = vec3(0.0);
    if (abs(N.x) > 0.5) { T = vec3(0.0, -sign(N.x), 0.0); } 
    else { T = vec3(sign(N.y), 0.0, 0.0); }
    vec3 B = vec3(0.0, 0.0, -1.0); 

    // 2. 九宫格区域判定
    bool isFrameX = (uv.x < tx) || (uv.x > 1.0 - tx);
    bool isFrameY = (uv.y < ty) || (uv.y > 1.0 - ty);
    
    if (isFrameX || isFrameY) {
        // --- 渲染画框本体 (不受视差影响，保持在最外层) ---
        vec2 frameUV = uv;
        if (uv.x < tx) { frameUV.x = uv.x / tx * 0.15; }
        else if (uv.x > 1.0 - tx) { frameUV.x = 0.85 + (uv.x - (1.0 - tx)) / tx * 0.15; }
        else { frameUV.x = 0.15 + (uv.x - tx) / (1.0 - 2.0 * tx) * 0.70; }
        
        if (uv.y < ty) { frameUV.y = uv.y / ty * 0.15; }
        else if (uv.y > 1.0 - ty) { frameUV.y = 0.85 + (uv.y - (1.0 - ty)) / ty * 0.15; }
        else { frameUV.y = 0.15 + (uv.y - ty) / (1.0 - 2.0 * ty) * 0.70; }
        
        albedo = Texel(u_frameTex, frameUV);
        vec3 sampledNormal = Texel(u_frameNormal, frameUV).xyz;
        localNormal = normalize(sampledNormal * 2.0 - 1.0);
    } else {
        // // --- 渲染画心：【核心魔法】视差内部映射 (Interior Parallax) ---
        
        // // 将世界坐标下的视线方向转换为切线空间
        // vec3 tangentViewDir = normalize(vec3(
        //     dot(u_viewDir, T),
        //     dot(u_viewDir, B),
        //     dot(u_viewDir, N)
        // ));
        
        // // 计算视差偏移量：视线越斜，偏移越大；0.12 代表画布凹进去的深度
        // // float depthScale = 0.05 + 0.07 * (1.0 - abs(tangentViewDir.z)); // 斜视时增加深度感
        // float depthScale = 0.05 + 0.02 * (1.0 - abs(tangentViewDir.z)); // 斜视时增加深度感
        // vec2 parallaxOffset = -(tangentViewDir.xy / tangentViewDir.z) * depthScale;

        // // 计算原本画作的 UV
        // vec2 paintingUV = vec2(
        //     (uv.x - tx) / (1.0 - 2.0 * tx),
        //     (uv.y - ty) / (1.0 - 2.0 * ty)
        // );
        
        // // 【加上视差偏移！】
        // paintingUV += parallaxOffset;

        // // 【精髓】：如果偏移后的 UV 超出了画心范围 (0~1)
        // // 意味着玩家在这个极度倾斜的角度，看到了画框的“内侧壁”！
        // if (paintingUV.x < 0.0 || paintingUV.x > 1.0 || paintingUV.y < 0.0 || paintingUV.y > 1.0) {
        //     // 给内侧壁涂上深邃的暗木头色，并加上极强的阴影，立体感瞬间爆炸！
        //     albedo = vec4(0.15, 0.08, 0.05, 1.0); 
        //     localNormal = vec3(0.0, 0.0, 1.0); 
        // } else {
        //     albedo = Texel(u_paintingTex, paintingUV);
        //     localNormal = vec3(0.0, 0.0, 1.0);
        // }
        // --- 渲染画心：【核心魔法】视差内部映射 + 玻璃质感 ---
        
        // 将世界坐标下的视线方向转换为切线空间
        vec3 tangentViewDir = normalize(vec3(
            dot(u_viewDir, T),
            dot(u_viewDir, B),
            dot(u_viewDir, N)
        ));
        
        // 你优化过的视差偏移算法
        float depthScale = 0.05 + 0.02 * (1.0 - abs(tangentViewDir.z)); 
        vec2 parallaxOffset = -(tangentViewDir.xy / tangentViewDir.z) * depthScale;

        vec2 paintingUV = vec2(
            (uv.x - tx) / (1.0 - 2.0 * tx),
            (uv.y - ty) / (1.0 - 2.0 * ty)
        );
        paintingUV += parallaxOffset;

        if (paintingUV.x < 0.0 || paintingUV.x > 1.0 || paintingUV.y < 0.0 || paintingUV.y > 1.0) {
            // 画框内侧壁
            albedo = vec4(0.15, 0.08, 0.05, 1.0); 
            localNormal = vec3(0.0, 0.0, 1.0); 
        } else {
            // 1. 获取底层偏移后的油画颜色
            vec4 canvasColor = Texel(u_paintingTex, paintingUV);
            
            // ==========================================
            // 【新增】玻璃光学模拟 (Glass Material)
            // ==========================================
            vec3 glassNormal = vec3(0.0, 0.0, 1.0); // 玻璃表面是绝对平坦的
            
            // 2. 菲涅尔边缘泛白 (Fresnel Reflection)
            // tangentViewDir.z 在切线空间中等同于 dot(Normal, ViewDir)
            // 视线越垂直于屏幕，值越接近0；视线越倾斜（侧面看），值越接近1
            float fresnel = pow(1.0 - max(tangentViewDir.z, 0.0), 3.0);
            vec3 envColor = vec3(0.7, 0.8, 0.9); // 模拟空旷房间的冷色调天光反射
            float fresnelIntensity = 0.4; // 玻璃边缘的最高反射强度
            
            // 3. 移动的镜面伪高光 (Fake Specular Highlight)
            // 在局部空间假设一个固定光源 (比如右上角)，当玩家走动导致视线变化时，高光会在玻璃上滑动
            vec3 fakeLightDir = normalize(vec3(0.5, 0.5, 0.8)); 
            vec3 halfVector = normalize(fakeLightDir + tangentViewDir);
            float specular = pow(max(dot(glassNormal, halfVector), 0.0), 64.0); // 64.0 是高光锐度，数值越大光点越小越亮
            float specularIntensity = 0.6; // 高光亮度
            
            // 4. 光学混合
            // 先将画作颜色与环境光按菲涅尔比例混合，然后再叠加纯白的高光
            vec3 finalColor = mix(canvasColor.rgb, envColor, fresnel * fresnelIntensity);
            // vec3 finalColor = canvasColor.rgb + (envColor * fresnel * fresnelIntensity);
            finalColor += vec3(1.0) * specular * specularIntensity; 
            
            albedo = vec4(finalColor, 1.0);
            
            // 5. 法线抹平：用平滑的玻璃法线覆盖画作本身的法线
            localNormal = glassNormal; 
        }
    }
    
    // 3. 转回世界空间写入 G-Buffer
    vec3 worldNormal = normalize(T * localNormal.x + B * localNormal.y + N * localNormal.z);
    
    love_Canvases[0] = albedo;
    love_Canvases[1] = vec4(worldNormal * 0.5 + 0.5, 1.0);
    love_Canvases[2] = vec4(u_depth / u_maxDepth, 0.0, 0.0, 1.0);
}