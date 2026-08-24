return [[
    extern Image depthTex;    // 深度缓冲
    extern Image mapTex;      // 显卡里的微型地图
    extern vec2 mapSize;      // 地图尺寸 (比如 10x8)
    
    // 玩家状态
    extern vec3 playerPos;    // x, y, dir
    extern float fov;
    
    // 光源数据 (支持最多 10 个动态光源！)
    extern int numLights;
    extern vec2 lightPos[10];
    extern vec3 lightColor[10];
    extern float lightRadius[10];

    // GPU 内部的“极速次级射线”阴影检测
    bool checkShadowCore(vec2 worldPos, vec2 lPos) {
        vec2 rayDir = lPos - worldPos;
        float maxDist = length(rayDir);
        rayDir = normalize(rayDir);
        
        // 阴影偏移：防止起点就在墙皮表面导致自己挡住自己
        vec2 startPos = worldPos + rayDir * 0.05;
        
        // DDA 初始网格坐标
        ivec2 mapPos = ivec2(floor(startPos));
        
        // 防止除以 0 的安全写法
        vec2 deltaDist = vec2(
            (rayDir.x == 0.0) ? 99999.0 : abs(1.0 / rayDir.x),
            (rayDir.y == 0.0) ? 99999.0 : abs(1.0 / rayDir.y)
        );
        
        ivec2 stepDir;
        vec2 sideDist;
        
        // 初始化 DDA 步进方向和初始距离
        if (rayDir.x < 0.0) {
            stepDir.x = -1;
            sideDist.x = (startPos.x - float(mapPos.x)) * deltaDist.x;
        } else {
            stepDir.x = 1;
            sideDist.x = (float(mapPos.x) + 1.0 - startPos.x) * deltaDist.x;
        }
        
        if (rayDir.y < 0.0) {
            stepDir.y = -1;
            sideDist.y = (startPos.y - float(mapPos.y)) * deltaDist.y;
        } else {
            stepDir.y = 1;
            sideDist.y = (float(mapPos.y) + 1.0 - startPos.y) * deltaDist.y;
        }
        
        // 开启纯正的 DDA 步进 (绝不遗漏任何一个网格！)
        for (int i = 0; i < 50; i++) {
            // 采样当前网格的颜色
            vec2 uv = (vec2(mapPos) + 0.5) / mapSize;
            
            // 安全锁：防止越界采样到奇怪的颜色
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
            
            float isWall = Texel(mapTex, uv).r;
            if (isWall > 0.5) {
                return true; // 绝对精确地撞墙了！
            }
            
            // 瞬间跳向下一个网格的交界处 (毫无冗余，极速推进)
            if (sideDist.x < sideDist.y) {
                if (sideDist.x > maxDist) break; // 已经摸到光源了，没有被挡住
                sideDist.x += deltaDist.x;
                mapPos.x += stepDir.x;
            } else {
                if (sideDist.y > maxDist) break;
                sideDist.y += deltaDist.y;
                mapPos.y += stepDir.y;
            }
        }
        
        return false;
    }
    
    float getLightVisibility(vec2 worldPos, vec2 lPos) {
        vec2 dir = normalize(lPos - worldPos);
        // 假设光源是一个半径为 0.15 米的实体火球
        // 计算出垂直于光线的切线 (左右偏移量)
        vec2 tangent = vec2(-dir.y, dir.x) * 0.15; 
        
        float visibility = 0.0;
        
        // 我们不再只发射 1 条射线，而是发射 3 条！
        // 分别射向光源的中心、左边缘和右边缘
        if (!checkShadowCore(worldPos, lPos)) visibility += 0.5;           // 中心光线占 50% 亮度
        if (!checkShadowCore(worldPos, lPos + tangent)) visibility += 0.25; // 左边缘占 25%
        if (!checkShadowCore(worldPos, lPos - tangent)) visibility += 0.25; // 右边缘占 25%
        
        // 返回最终的可见度 (0.0=全黑, 0.25~0.75=灰色的半影, 1.0=全亮)
        return visibility;
    }

    vec4 effect(vec4 color, Image albedoTex, vec2 tc, vec2 sc) {
        vec4 albedo = Texel(albedoTex, tc);
        float depth = Texel(depthTex, tc).r;

        // return albedo; // 【调试用】先不计算光照，直接输出原色
        
        // 如果深度大于 29，说明是天空盒，不计算光照
        if (depth > 29.0) return albedo;

        // ==========================================
        // 【逆向工程】从深度图还原 3D 世界坐标！
        // ==========================================
        float cameraX = 2.0 * tc.x - 1.0;
        float rayAngle = playerPos.z + (cameraX * fov / 2.0);
        
        // 修正鱼眼，算回真实的欧几里得距离
        float trueDist = depth / cos(rayAngle - playerPos.z);
        
        vec2 worldPos;
        worldPos.x = playerPos.x + cos(rayAngle) * trueDist;
        worldPos.y = playerPos.y + sin(rayAngle) * trueDist;

        // ==========================================
        // GPU 光照计算开始
        // ==========================================
        vec3 finalLight = vec3(0.05); // 环境光
        
        // 【优化】玩家提灯：使用 smoothstep 替代线性衰减
        float lanternRadius = 5.5;
        if (depth < lanternRadius) {
            // smoothstep 会生成一条完美的 "S型" 缓动曲线
            // 边缘会极其柔和地融入黑暗，再也不会有生硬的切断感
            float falloff = smoothstep(lanternRadius, 0.0, depth);
            // 亮度调低一点(0.4)，让它更像一盏微弱的提灯，而不是探照灯
            finalLight += vec3(0.4) * falloff; 
        }

        // 遍历场景光源
        for(int i = 0; i < 10; i++) {
            if (i >= numLights) break;
            
            float distToLight = distance(worldPos, lightPos[i]);
            if (distToLight < lightRadius[i]) {
                
                // 【优化】调用新的软阴影采样器
                float visibility = getLightVisibility(worldPos, lightPos[i]);
                
                // 只有可见度大于 0 (哪怕只是擦到一点光) 才计算颜色
                if (visibility > 0.0) {
                    float attenuation = max(0.0, 1.0 - (distToLight / lightRadius[i]));
                    // 继续使用二次方衰减保证中心亮，边缘暗
                    float falloff = attenuation * attenuation;
                    
                    // 最终叠加颜色时，乘以可见度百分比 (visibility)
                    finalLight += lightColor[i] * falloff * visibility;
                }
            }
        }
        
        return vec4(albedo.rgb * min(finalLight, vec3(1.0)), albedo.a);
    }
]]