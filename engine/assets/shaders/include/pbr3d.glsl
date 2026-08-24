// 引擎 PBR 前向着色核心（经 ShaderPreprocessor 的 #include 引用，不单独编译）。
//
// 这里只放引擎认识的东西：自定义 MVP、方向光 + 半球环境光、法线/PBR/AO 贴图、
// 阴影图采样、曝光与高度雾。任何一款游戏专属的表面效果都不属于本文件——
// 它们通过下面两个 hook 从游戏侧注入，engine/ 因此不需要知道 games/ 的存在。
//
// ===== 用法 A：直接用（无扩展）=====
//   #include "engine/assets/shaders/include/pbr3d.glsl"
// 即 engine/assets/shaders/Pbr3D.lua 的全部内容。
//
// ===== 用法 B：注入游戏专属效果 =====
//   #define PBR_SURFACE_HOOK          // 想改 albedo/normal/roughness/... 时声明
//   #define PBR_SHADE_HOOK            // 想接管/叠加最终着色结果时声明
//   #include "engine/assets/shaders/include/pbr3d.glsl"
//   #ifdef PIXEL
//   uniform ...;                      // 游戏自己的 uniform
//   void pbrSurfaceHook(inout PbrSurface surface, vec2 uv) { ... }
//   vec3 pbrShadeHook(vec3 lit, PbrSurface surface, vec2 uv) { ... }
//   #endif
//
// hook 的函数体写在 #include 之后：本文件在 #ifdef 保护下给出了函数原型，
// GLSL 允许"先声明后定义"，所以 effect() 能调用尚未出现的游戏函数。
// #define 必须写在 #include 之前——展开是纯文本的，GLSL 预处理器按顺序求值。
//
// hook 只在被 #define 的变体里存在。没声明的着色器编译出的代码与手写版逐指令等价，
// 不为"可能有游戏扩展"付出任何运行时代价。

varying vec3 v_normal;
varying vec3 v_worldPos;
varying vec2 v_uv;

#ifdef VERTEX
uniform mat4 u_model;
uniform mat4 u_normalMatrix;
uniform mat4 u_viewProj;
attribute vec3 VertexNormal;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    // 注意：完全绕过 LÖVE 的 transform_projection，直接输出裁剪空间坐标。
    // 法线走逆转置矩阵，非均匀缩放下光照方向也保持正确。
    vec4 world = u_model * vertex_position;
    v_normal = mat3(u_normalMatrix[0].xyz, u_normalMatrix[1].xyz, u_normalMatrix[2].xyz) * VertexNormal;
    v_worldPos = world.xyz;
    v_uv = VertexTexCoord.xy;
    return u_viewProj * world;
}
#endif

#ifdef PIXEL
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
#endif

// ===== 环境与光照（engine/rendering/Environment.lua 下发）=====
uniform vec3 u_lightDir; // 指向光源的单位向量（世界空间）
uniform vec3 u_ambient;  // 环境光
uniform vec3 u_skyIrradiance;
uniform vec3 u_horizonIrradiance;
uniform vec3 u_groundIrradiance;
uniform vec3 u_sunColor;
uniform float u_sunIntensity;
uniform vec3 u_skyColorTop;      // 天空辐亮度（水面等镜面反射用，非辐照度）
uniform vec3 u_skyColorHorizon;
uniform vec3 u_fogColor;
uniform float u_fogStart;
uniform float u_fogDensity;
uniform float u_fogHeightFalloff;
uniform float u_exposure;
uniform vec3 u_cameraPos;

// ===== 材质（engine/rendering/LevelMesh.lua 的 applyMaterial 下发）=====
uniform vec4 u_materialColor;
uniform float u_metallic;
uniform float u_roughness;
uniform float u_ao;
uniform float u_normalScale;
uniform float u_hasNormalMap;
uniform float u_hasPbrMap;
uniform float u_hasRoughnessMap;
uniform float u_hasAoMap;
uniform float u_hasAlphaMask;
uniform float u_alphaCutoff;
uniform Image u_normalTex;
uniform Image u_pbrTex;
uniform Image u_roughnessTex;
uniform Image u_aoTex;
uniform Image u_alphaMask;

// ===== 阴影（engine/rendering/ShadowMap.lua 下发）=====
uniform float u_hasShadowMap;
uniform float u_shadowStrength;
uniform float u_shadowBias;
uniform float u_shadowFadeStart;
uniform float u_shadowRange;
uniform vec3 u_shadowCenter;
uniform vec2 u_shadowTexelSize;
uniform mat4 u_lightViewProj;
uniform Image u_shadowMap;

const float PI = 3.14159265359;

// 着色前的表面属性。hook 收到的就是它——游戏改这个结构体，而不是改引擎源码。
struct PbrSurface {
    vec3 albedo;
    vec3 normal;    // 世界空间，已归一化
    float metallic;
    float roughness;
    float ao;
    float alpha;
};

#ifdef PBR_SURFACE_HOOK
// 采样完贴图、着色之前调用。用于地表状态、污渍、覆雪等改写表面属性的效果。
void pbrSurfaceHook(inout PbrSurface surface, vec2 uv);
#endif

#ifdef PBR_SHADE_HOOK
// 着色之后、tonemap/雾之前调用。返回值替换 lit，可叠加也可完全接管（如水面）。
vec3 pbrShadeHook(vec3 lit, PbrSurface surface, vec2 uv);
#endif

// 未设置 u_sunColor/u_sunIntensity 的场景（如只发方向光的简单 sample）退化为
// 白色单位强度太阳，而不是全黑。hook 里也该用这两个函数取太阳参数。
vec3 pbrSunColor()
{
    return dot(u_sunColor, u_sunColor) > 0.0 ? u_sunColor : vec3(1.0);
}

float pbrSunIntensity()
{
    return u_sunIntensity > 0.0 ? u_sunIntensity : 1.0;
}

// 切线空间法线贴图 → 世界空间。切线基由屏幕导数现场求，网格不需要烘焙 tangent
// （代价是每像素几条 dFdx/dFdy；换来的是顶点格式只需 pos3+uv2+norm3）。
vec3 pbrNormalFromMap(vec3 baseNormal, vec2 uv)
{
    if (u_hasNormalMap < 0.5) return normalize(baseNormal);
    vec3 tangentNormal = Texel(u_normalTex, uv).xyz * 2.0 - 1.0;
    tangentNormal.xy *= u_normalScale;
    tangentNormal = normalize(tangentNormal);

    vec3 dp1 = dFdx(v_worldPos);
    vec3 dp2 = dFdy(v_worldPos);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);
    vec3 n = normalize(baseNormal);
    vec3 tangentCandidate = dp1 * duv2.y - dp2 * duv1.y;
    vec3 bitangentCandidate = -dp1 * duv2.x + dp2 * duv1.x;
    if (dot(tangentCandidate, tangentCandidate) < 0.0000001
        || dot(bitangentCandidate, bitangentCandidate) < 0.0000001) {
        return n;
    }
    vec3 t = normalize(tangentCandidate);
    vec3 b = normalize(bitangentCandidate);
    return normalize(mat3(t, b, n) * tangentNormal);
}

float distributionGGX(vec3 n, vec3 h, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float denom = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / max(PI * denom * denom, 0.0001);
}

float geometrySchlickGGX(float ndotv, float roughness)
{
    float r = roughness + 1.0;
    float k = r * r / 8.0;
    return ndotv / max(ndotv * (1.0 - k) + k, 0.0001);
}

float geometrySmith(vec3 n, vec3 v, vec3 l, float roughness)
{
    return geometrySchlickGGX(max(dot(n, v), 0.0), roughness)
        * geometrySchlickGGX(max(dot(n, l), 0.0), roughness);
}

vec3 fresnelSchlick(float cosine, vec3 f0)
{
    return f0 + (1.0 - f0) * pow(1.0 - cosine, 5.0);
}

vec3 fresnelSchlickRoughness(float cosine, vec3 f0, float roughness)
{
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - cosine, 5.0);
}

// 3x3 PCF + 距离淡出。返回 0..1 的遮挡比例（未绑定 shadow map 时恒为 0）。
float pbrShadowOcclusion(vec3 normal, vec3 lightDirection)
{
    if (u_hasShadowMap < 0.5) return 0.0;
    vec4 lightClip = u_lightViewProj * vec4(v_worldPos, 1.0);
    vec3 projected = lightClip.xyz / max(lightClip.w, 0.0001);
    projected = projected * 0.5 + 0.5;
    if (projected.x <= 0.001 || projected.x >= 0.999 || projected.y <= 0.001 || projected.y >= 0.999
        || projected.z <= 0.001 || projected.z >= 0.999) return 0.0;

    float bias = max(u_shadowBias * (1.0 - max(dot(normal, lightDirection), 0.0)), u_shadowBias * 0.35);
    float occluded = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float closest = Texel(u_shadowMap, projected.xy + vec2(float(x), float(y)) * u_shadowTexelSize).r;
            occluded += projected.z - bias > closest ? 1.0 : 0.0;
        }
    }
    float dx = v_worldPos.x - u_shadowCenter.x;
    float dz = v_worldPos.z - u_shadowCenter.z;
    float distanceFade = 1.0 - smoothstep(u_shadowFadeStart, u_shadowRange, length(vec2(dx, dz)));
    return (occluded / 9.0) * distanceFade;
}

// albedo + alpha 单独一步：alpha cutoff 要在采样其余贴图之前 discard，
// 树叶这类大面积 alpha test 材质才不会白白付出法线/PBR 贴图的采样开销。
vec4 pbrSampleAlbedo(vec4 color, Image tex, vec2 uv)
{
    vec4 albedoSample = Texel(tex, uv) * color * u_materialColor;
    if (u_hasAlphaMask > 0.5) {
        albedoSample.a *= Texel(u_alphaMask, uv).r;
    }
    return albedoSample;
}

PbrSurface pbrSampleSurface(vec4 albedoSample, vec2 uv)
{
    PbrSurface surface;
    surface.albedo = albedoSample.rgb;
    surface.alpha = albedoSample.a;
    surface.metallic = clamp(u_metallic, 0.0, 1.0);
    surface.roughness = clamp(u_roughness, 0.04, 1.0);
    surface.ao = clamp(u_ao, 0.0, 1.0);
    if (u_hasPbrMap > 0.5) {
        // 打包图约定：R=metallic, G=roughness, B=ao（一次采样顶三次）
        vec3 pbrValues = Texel(u_pbrTex, uv).rgb;
        surface.metallic = pbrValues.r;
        surface.roughness = clamp(pbrValues.g, 0.04, 1.0);
        surface.ao = pbrValues.b;
    } else {
        if (u_hasRoughnessMap > 0.5) surface.roughness = clamp(Texel(u_roughnessTex, uv).r, 0.04, 1.0);
        if (u_hasAoMap > 0.5) surface.ao = Texel(u_aoTex, uv).r;
    }
    surface.normal = pbrNormalFromMap(v_normal, uv);
    return surface;
}

// Cook-Torrance 直接光 + 半球环境光近似。返回线性 HDR 亮度（未 tonemap）。
vec3 pbrShade(PbrSurface surface)
{
    vec3 n = surface.normal;
    vec3 l = normalize(u_lightDir);
    vec3 v = normalize(u_cameraPos - v_worldPos);
    vec3 h = normalize(l + v);
    float ndotl = max(dot(n, l), 0.0);
    float ndotv = max(dot(n, v), 0.001);

    vec3 f0 = mix(vec3(0.04), surface.albedo, surface.metallic);
    float ndf = distributionGGX(n, h, surface.roughness);
    float geometry = geometrySmith(n, v, l, surface.roughness);
    vec3 fresnel = fresnelSchlick(max(dot(h, v), 0.0), f0);
    vec3 specular = ndf * geometry * fresnel / max(4.0 * ndotv * ndotl, 0.001);
    vec3 kD = (vec3(1.0) - fresnel) * (1.0 - surface.metallic);
    vec3 direct = (kD * surface.albedo / PI + specular) * pbrSunColor() * pbrSunIntensity() * ndotl;
    direct *= 1.0 - pbrShadowOcclusion(n, l) * u_shadowStrength;

    float hemi = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
    float horizonWeight = 1.0 - abs(n.y);
    vec3 irradiance = mix(u_groundIrradiance, u_skyIrradiance, hemi);
    vec3 horizonIrradiance = dot(u_horizonIrradiance, u_horizonIrradiance) > 0.0
        ? u_horizonIrradiance
        : mix(u_groundIrradiance, u_skyIrradiance, 0.5);
    irradiance = mix(irradiance, horizonIrradiance, horizonWeight * 0.38) + u_ambient;
    vec3 reflection = reflect(-v, n);
    vec3 reflectedEnvironment = mix(u_groundIrradiance, u_skyIrradiance,
        clamp(reflection.y * 0.5 + 0.5, 0.0, 1.0));
    vec3 environmentFresnel = fresnelSchlickRoughness(ndotv, f0, surface.roughness);
    vec3 indirectDiffuse = surface.albedo * (1.0 - surface.metallic) * irradiance;
    vec3 indirectSpecular = reflectedEnvironment * environmentFresnel * (1.0 - surface.roughness * 0.72);
    return (indirectDiffuse + indirectSpecular) * surface.ao + direct;
}

// 曝光 tonemap + 指数高度雾。雾色同样过 tonemap，远处才不会比天空亮一截。
vec3 pbrTonemapFog(vec3 lit)
{
    float exposure = (u_exposure > 0.0) ? u_exposure : 1.0;
    lit = vec3(1.0) - exp(-lit * exposure);
    float viewDistance = length(u_cameraPos - v_worldPos);
    float heightDensity = exp(-max(v_worldPos.y, 0.0) * u_fogHeightFalloff);
    float fogDistance = max(viewDistance - u_fogStart, 0.0);
    float fogOpticalDepth = fogDistance * u_fogDensity * heightDensity;
    float fog = 1.0 - exp(-fogOpticalDepth * fogOpticalDepth);
    vec3 exposedFogColor = vec3(1.0) - exp(-u_fogColor * exposure);
    return mix(lit, exposedFogColor, clamp(fog, 0.0, 1.0));
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 albedoSample = pbrSampleAlbedo(color, tex, uv);
    if (albedoSample.a < u_alphaCutoff) discard;

    PbrSurface surface = pbrSampleSurface(albedoSample, uv);
#ifdef PBR_SURFACE_HOOK
    pbrSurfaceHook(surface, uv);
#endif

    vec3 lit = pbrShade(surface);
#ifdef PBR_SHADE_HOOK
    lit = pbrShadeHook(lit, surface, uv);
#endif

    return vec4(pbrTonemapFog(lit), surface.alpha);
}
#endif
