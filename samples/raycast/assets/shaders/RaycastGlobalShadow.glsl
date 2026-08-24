extern Image u_normalTex;
extern Image u_mapTex;
extern Image u_depthTex;
extern Image u_statueTex;
extern vec3 u_sunDirection;

extern vec2 u_playerPos;
extern float u_playerDir;
extern float u_fov;
extern float u_zPlayer;
extern float u_screenHeight;
extern float u_screenWidth;
extern vec2 u_mapSize;

extern float u_maxDepth;
extern float u_maxMapHeight;

const float SHADOW_NONE = 0.0;
const float SHADOW_SOLID = 1.0;
const float SHADOW_ALPHA = 2.0;

float decodeShadowMode(vec4 mapSample) {
    return floor(mapSample.r * 10.0 + 0.5);
}

float decodeBlockHeight(vec4 mapSample) {
    return mapSample.g * u_maxMapHeight;
}

float getShadow(vec3 rayPos, vec3 sunDir) {
    vec2 mapPos = floor(rayPos.xy);
    vec2 rayDir2D = sunDir.xy;

    if (abs(rayDir2D.x) < 0.0001) rayDir2D.x = 0.0001;
    if (abs(rayDir2D.y) < 0.0001) rayDir2D.y = 0.0001;

    vec2 deltaDist = abs(1.0 / rayDir2D);
    vec2 stepSign = sign(rayDir2D);
    vec2 sideDist;

    if (rayDir2D.x < 0.0) sideDist.x = (rayPos.x - mapPos.x) * deltaDist.x;
    else                  sideDist.x = (mapPos.x + 1.0 - rayPos.x) * deltaDist.x;

    if (rayDir2D.y < 0.0) sideDist.y = (rayPos.y - mapPos.y) * deltaDist.y;
    else                  sideDist.y = (mapPos.y + 1.0 - rayPos.y) * deltaDist.y;

    float currentT = 0.0;

    {
        vec2 startUV = vec2((mapPos.x + 0.5) / u_mapSize.x, (mapPos.y + 0.5) / u_mapSize.y);
        vec4 startSample = Texel(u_mapTex, startUV);
        float startShadowMode = decodeShadowMode(startSample);
        float startHeight = decodeBlockHeight(startSample);

        if (startShadowMode == SHADOW_ALPHA) {
            vec2 statueCenter = mapPos + vec2(0.5);
            vec2 planeN = normalize(sunDir.xy);
            float denom = dot(sunDir.xy, planeN);
            if (abs(denom) > 0.001) {
                float t_hit = dot(statueCenter - rayPos.xy, planeN) / denom;
                if (t_hit > -0.6) {
                    vec3 hitPoint = rayPos + t_hit * sunDir;
                    vec2 hAxis = vec2(-planeN.y, planeN.x);
                    float u_coord = dot(hitPoint.xy - statueCenter, hAxis) + 0.5;
                    float v_coord = 1.0 - clamp(hitPoint.z / max(startHeight, 0.001), 0.0, 1.0);
                    if (u_coord >= 0.0 && u_coord <= 1.0) {
                        float alpha = Texel(u_statueTex, vec2(u_coord, v_coord)).a;
                        if (alpha > 0.1) return 0.0;
                    }
                }
            }
        }
    }

    for (int i = 0; i < 150; i++) {
        if (sideDist.x < sideDist.y) {
            currentT = sideDist.x;
            sideDist.x += deltaDist.x;
            mapPos.x += stepSign.x;
        } else {
            currentT = sideDist.y;
            sideDist.y += deltaDist.y;
            mapPos.y += stepSign.y;
        }

        if (mapPos.x < 0.0 || mapPos.x >= u_mapSize.x || mapPos.y < 0.0 || mapPos.y >= u_mapSize.y) {
            break;
        }

        float currentZ = rayPos.z + currentT * sunDir.z;
        if (currentZ > u_maxMapHeight) break;

        vec2 mapUV = vec2((mapPos.x + 0.5) / u_mapSize.x, (mapPos.y + 0.5) / u_mapSize.y);
        vec4 mapSample = Texel(u_mapTex, mapUV);
        float shadowMode = decodeShadowMode(mapSample);
        float blockHeight = decodeBlockHeight(mapSample);

        if (shadowMode > SHADOW_NONE) {
            bool castShadow = false;

            if (shadowMode == SHADOW_SOLID) {
                castShadow = (currentZ < blockHeight);
            } else if (shadowMode == SHADOW_ALPHA) {
                vec2 statueCenter = mapPos + vec2(0.5);
                vec2 planeN = normalize(sunDir.xy);
                float denom = dot(sunDir.xy, planeN);
                if (abs(denom) > 0.001) {
                    float t_hit = dot(statueCenter - rayPos.xy, planeN) / denom;
                    if (t_hit > 0.0) {
                        vec3 hitPoint = rayPos + t_hit * sunDir;
                        vec2 hAxis = vec2(-planeN.y, planeN.x);
                        float hOffset = dot(hitPoint.xy - statueCenter, hAxis);
                        float u_coord = hOffset + 0.5;
                        float v_coord = 1.0 - clamp(hitPoint.z / max(blockHeight, 0.001), 0.0, 1.0);
                        if (u_coord >= 0.0 && u_coord <= 1.0) {
                            float alpha = Texel(u_statueTex, vec2(u_coord, v_coord)).a;
                            castShadow = (alpha > 0.1);
                        }
                    }
                }
            }

            if (castShadow) return 0.0;
        }
    }

    return 1.0;
}

vec4 effect(vec4 color, Image albedoTex, vec2 texture_coords, vec2 screen_coords) {
    vec4 albedo = Texel(albedoTex, texture_coords);
    vec3 normal = Texel(u_normalTex, texture_coords).xyz * 2.0 - 1.0;

    if (normal.z < -0.5) return albedo;

    vec3 sunDir = normalize(u_sunDirection);
    float NdotL = dot(normal, sunDir);
    vec3 finalColor;

    if (NdotL > 0.05) {
        finalColor = albedo.rgb * vec3(1.2, 1.1, 0.9);
    } else {
        finalColor = albedo.rgb * vec3(0.15, 0.25, 0.4);
    }

    float shadow = 1.0;
    vec3 rayPos;
    bool canCastShadow = false;

    float cameraX = (screen_coords.x / u_screenWidth) * 2.0 - 1.0;
    float angleDiff = cameraX * u_fov / 2.0;
    float rayAngle = u_playerDir + angleDiff;

    if (normal.z > 0.5) {
        float p = screen_coords.y - (u_screenHeight / 2.0);
        if (p > 0.0) {
            float rowDistance = (u_zPlayer * u_screenHeight) / p;
            float trueDist = rowDistance / cos(angleDiff);
            rayPos = vec3(
                u_playerPos.x + trueDist * cos(rayAngle),
                u_playerPos.y + trueDist * sin(rayAngle),
                0.0
            );
            canCastShadow = true;
        }
    } else {
        float rawDepth = Texel(u_depthTex, texture_coords).r;
        if (rawDepth < 0.99) {
            float correctedDist = rawDepth * u_maxDepth;
            float trueDist = correctedDist / cos(angleDiff);
            float p = (u_screenHeight / 2.0) - screen_coords.y;
            float pixelZ = u_zPlayer + (p * correctedDist / u_screenHeight);
            rayPos = vec3(
                u_playerPos.x + trueDist * cos(rayAngle),
                u_playerPos.y + trueDist * sin(rayAngle),
                pixelZ
            );
            canCastShadow = true;
        }
    }

    if (canCastShadow) {
        rayPos += normal * 0.03;

        vec3 right = normalize(cross(sunDir, vec3(0.0, 0.0, 1.0)));
        vec3 up = normalize(cross(right, sunDir));

        float noise = fract(
            sin(dot(screen_coords.xy, vec2(12.9898, 78.233)))
            * 43758.5453
        );

        float angle = noise * 6.2831853;
        float s = sin(angle);
        float c = cos(angle);
        mat2 rot = mat2(c, -s, s, c);

        vec2 poisson[16];
        poisson[0] = vec2(0.130, 0.130);
        poisson[1] = vec2(-0.130, 0.130);
        poisson[2] = vec2(0.130, -0.130);
        poisson[3] = vec2(-0.130, -0.130);
        poisson[4] = vec2(0.4, 0.0);
        poisson[5] = vec2(-0.4, 0.0);
        poisson[6] = vec2(0.0, 0.4);
        poisson[7] = vec2(0.0, -0.4);
        poisson[8] = vec2(0.6, 0.3);
        poisson[9] = vec2(-0.6, 0.3);
        poisson[10] = vec2(0.6, -0.3);
        poisson[11] = vec2(-0.6, -0.3);
        poisson[12] = vec2(0.3, 0.6);
        poisson[13] = vec2(-0.3, 0.6);
        poisson[14] = vec2(0.3, -0.6);
        poisson[15] = vec2(-0.3, -0.6);

        float spread = 0.015;

        shadow = 0.0;

        for (int i = 0; i < 16; i++) {
            vec2 rotated = rot * poisson[i];

            vec3 offsetDir = normalize(
                sunDir +
                right * rotated.x * spread +
                up * rotated.y * spread
            );

            shadow += getShadow(rayPos, offsetDir);
        }

        shadow /= 16.0;
    }

    finalColor *= mix(vec3(0.3, 0.4, 0.5), vec3(1.0), shadow);
    finalColor = clamp(finalColor, 0.0, 1.0);
    return vec4(finalColor, albedo.a);
}
