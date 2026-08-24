-- 长筱战场的 PBR 变体：引擎核心 + 可选水面库 + 本作专属的"地表状态"表面效果。
--
-- 地表状态是一张随战斗累积的 RGBA 图（games/nagashino/rendering/BattlefieldStamps.lua
-- 逐帧盖章渲染，见 engine/rendering/SurfaceStamps.lua）：
--   R = churn 践踏翻浆   G = wetness 湿度   B = crater 弹坑   A = blood 血渍
-- 本着色器把它投影回世界 XZ，改写 albedo / roughness / normal。这些都是本作玩法
-- 产物，不属于引擎——所以走 PBR_SURFACE_HOOK 注入，engine/ 不认识这些 uniform。
--
-- 材质侧配套 games/nagashino/rendering/BattlefieldMaterial.lua 下发逐材质开关。
return [[
#define PBR_SURFACE_HOOK
#define PBR_SHADE_HOOK
#include "engine/assets/shaders/include/pbr3d.glsl"
#include "engine/assets/shaders/include/water.glsl"

#ifdef PIXEL
uniform float u_hasBattlefieldState;      // 场景是否绑定了状态图（逐帧）
uniform float u_receivesBattlefieldState; // 该材质是否吃状态图（逐材质）
uniform vec4 u_battlefieldBounds;         // 状态图覆盖的世界范围 (minX, minZ, maxX, maxZ)
uniform Image u_battlefieldState;
uniform Image u_mudTrackTexture;
uniform Image u_craterDirtTexture;
uniform Image u_craterNormalTexture;
uniform Image u_craterRoughnessTexture;

void pbrSurfaceHook(inout PbrSurface surface, vec2 uv)
{
    if (u_hasBattlefieldState < 0.5 || u_receivesBattlefieldState < 0.5) return;

    vec2 stateSize = u_battlefieldBounds.zw - u_battlefieldBounds.xy;
    vec2 stateUv = (v_worldPos.xz - u_battlefieldBounds.xy) / max(stateSize, vec2(0.001));
    if (stateUv.x <= 0.0 || stateUv.x >= 1.0 || stateUv.y <= 0.0 || stateUv.y >= 1.0) return;

    vec2 craterDetailUv = v_worldPos.xz * 0.58 + vec2(0.31, 0.17);
    vec2 stampUv = vec2(stateUv.x, 1.0 - stateUv.y);
    vec4 state = Texel(u_battlefieldState, stampUv);
    // 盖章值是无上限累积的，用 1-exp(-k*x) 压到 0..1 并保留"越踩越快饱和"的手感
    float churn = 1.0 - exp(-state.r * 3.6);
    float wetness = 1.0 - exp(-state.g * 3.4);
    float crater = 1.0 - exp(-state.b * 4.4);
    float blood = 1.0 - exp(-state.a * 4.8);

    vec3 trackMud = Texel(u_mudTrackTexture, v_worldPos.xz * 0.22 + vec2(0.17, 0.41)).rgb;
    vec3 craterDirt = Texel(u_craterDirtTexture, craterDetailUv).rgb;
    float craterRoughness = Texel(u_craterRoughnessTexture, craterDetailUv).r;
    float exposedMud = smoothstep(0.045, 0.55, churn);
    vec3 redBrownMud = trackMud * mix(vec3(1.0), vec3(0.68, 0.46, 0.30), churn * 0.72);

    vec3 albedo = surface.albedo;
    albedo = mix(albedo, redBrownMud, exposedMud * 0.90);
    albedo = mix(albedo, albedo * vec3(0.72, 0.52, 0.36), churn * 0.22);
    albedo = mix(albedo, craterDirt * vec3(0.56, 0.43, 0.30), crater * 0.82);
    albedo = mix(albedo, vec3(0.16, 0.018, 0.012), blood * 0.76);
    // 湿润与弹坑压暗地表；湿地同时更光滑（roughness 减），翻浆与弹坑更粗糙
    surface.albedo = albedo * (1.0 - wetness * 0.16 - crater * 0.10);

    float roughness = mix(surface.roughness, clamp(craterRoughness * 1.08, 0.18, 1.0), crater * 0.76);
    surface.roughness = clamp(roughness + churn * 0.19 + crater * 0.14 - wetness * 0.38 - blood * 0.16, 0.04, 1.0);

    if (crater > 0.001) {
        // 弹坑法线按"地面朝上"重建，再按强度混回原法线：坑洼起伏压过原始地表细节
        vec3 craterNormal = Texel(u_craterNormalTexture, craterDetailUv).xyz * 2.0 - 1.0;
        vec3 craterWorldNormal = normalize(vec3(craterNormal.x * 0.32, 1.0, craterNormal.y * 0.32));
        surface.normal = normalize(mix(surface.normal, craterWorldNormal, crater * 0.58));
    }
}
#endif
]]
