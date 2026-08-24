// 可选的水面着色库：实现 pbr3d.glsl 的 PBR_SHADE_HOOK，把标记为水面的材质
// 从常规 PBR 结果换成"波纹法线 + 天空反射 + 日光碎金 + 岸边碎浪"。
//
// 用法（必须在 pbr3d.glsl 之后 include；本文件依赖它的 PbrSurface / BRDF / uniform）：
//   #define PBR_SHADE_HOOK
//   #include "engine/assets/shaders/include/pbr3d.glsl"
//   #include "engine/assets/shaders/include/water.glsl"
// 材质侧配套 engine/rendering/WaterMaterial.lua 下发 uniform。
//
// 网格约定（用别的拓扑做水面时要么改网格 UV，要么别用这个库）：
//   * 水面朝上（+Y），切平面近似世界 XZ——波纹法线直接在世界空间构造。
//   * UV 的 v 轴横跨水体宽度 0..1，v=0/1 是岸边。深浅渐变和岸边碎浪都读它，
//     ribbon（河流条带）网格天然满足；平铺 UV 的大水面会得到错误的岸线。
//
// 非水面材质（u_waterSurface < 0.5）原样返回 lit，不产生任何额外采样。

#ifdef PIXEL
uniform float u_waterSurface;         // 0 = 普通材质（直接透传），1 = 走水面路径
uniform float u_time;
uniform vec2 u_flowDirection;
uniform vec3 u_waterShallowColor;
uniform vec3 u_waterDeepColor;

vec3 pbrShadeHook(vec3 lit, PbrSurface surface, vec2 uv)
{
    if (u_waterSurface < 0.5) return lit;

    vec3 l = normalize(u_lightDir);
    vec3 v = normalize(u_cameraPos - v_worldPos);
    vec3 sunColor = pbrSunColor();
    float sunIntensity = pbrSunIntensity();

    // 双层世界空间滚动法线：不同尺度/方向/速度叠加，破除平铺感与"大正弦塑料波"
    vec2 flow = u_flowDirection / max(length(u_flowDirection), 0.0001);
    vec2 uvA = v_worldPos.xz * 0.085 + flow * (u_time * 0.050);
    vec2 uvB = v_worldPos.xz * 0.230 - flow * (u_time * 0.027) + vec2(0.37, 0.11);
    vec3 mapA = Texel(u_normalTex, uvA).xyz * 2.0 - 1.0;
    vec3 mapB = Texel(u_normalTex, uvB).xyz * 2.0 - 1.0;
    // 波纹随距离衰减：远处大尺度波斑会把掠射菲涅尔反射调制成云状奶白斑块，
    // 压平后远景回归"平静水面的均匀天空反射"
    float waterDist = clamp(length(u_cameraPos - v_worldPos) / 90.0, 0.0, 1.0);
    vec2 ripple = (mapA.xy + mapB.xy * 0.55) * u_normalScale * (1.0 - waterDist * 0.72);
    vec3 waterN = normalize(vec3(ripple.x, 1.0, ripple.y)); // 水面朝上，切平面≈世界 XZ

    // 岸边→河心的深浅渐变：ribbon 网格的 UV v 跨河宽 0..1，v=0/1 是岸边
    float shore = 1.0 - abs(uv.y * 2.0 - 1.0);
    float depthFade = smoothstep(0.06, 0.62, shore);
    vec3 waterBody = mix(u_waterShallowColor, u_waterDeepColor, depthFade);

    float wNdotV = max(dot(waterN, v), 0.001);
    float wNdotL = max(dot(waterN, l), 0.0);
    // 菲涅尔用"平面几何法线"而不是波纹法线：波纹会大幅调制掠射角的 ndotv，
    // 把亮色天空反射打成大片云状奶斑。反射取色/太阳闪点仍用波纹法线保留波光。
    // 上限 0.72：远处不退化成整片全反射的白镜面
    float flatNdotV = max(dot(normalize(v_normal), v), 0.001);
    float waterFresnel = min(0.02 + 0.98 * pow(1.0 - flatNdotV, 5.0), 0.72);
    // 天空反射：反射向量越朝天顶越接近天空色。乘 2.4 做高度偏置——
    // 掠射时反射光谱学上取地平线色（灰白雾色），观感发"奶"；偏向更高处
    // 的蓝天让远水读作"倒映天空的深色水面"，是水面渲染的常用美术修正
    vec3 reflDir = reflect(-v, waterN);
    float upness = clamp(reflDir.y * 2.4, 0.0, 1.0);
    vec3 skyReflection = mix(u_skyColorHorizon, u_skyColorTop, pow(upness, 0.55));

    // 太阳高光：低 roughness GGX 配合波纹法线 → 碎金般的日光闪点。
    // 随距离增大粗糙度：远处波纹被 mip 平均成平面镜，低粗糙度会把低角度
    // 太阳反射成整片均匀亮带；摊开高光即恢复"远处水色变暗"的观感
    float waterRough = clamp(mix(u_roughness, 0.30, waterDist), 0.02, 1.0);
    vec3 wh = normalize(l + v);
    float glintSpec = distributionGGX(waterN, wh, waterRough)
        * geometrySmith(waterN, v, l, waterRough)
        / max(4.0 * wNdotV * wNdotL, 0.001);
    vec3 glintFresnel = fresnelSchlick(max(dot(wh, v), 0.0), vec3(0.02));
    // 0.45 压制眩光带：物理值在宽波纹+曝光下会摊成大面积奶白，观感优先
    vec3 sunGlint = glintSpec * glintFresnel * sunColor * sunIntensity * wNdotL * 0.45;

    // 水体颜色受环境辐照照明（吸收主导，直射只留一点穿透）
    float wHemi = clamp(waterN.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 waterIrradiance = mix(u_groundIrradiance, u_skyIrradiance, wHemi) + u_ambient;
    vec3 bodyLit = waterBody * (waterIrradiance + sunColor * sunIntensity * 0.10 * wNdotL);

    // 岸边碎浪：窄带白沫，用波纹图当噪声打碎边缘
    float foamNoise = 0.5 + 0.5 * mapB.x;
    float foam = smoothstep(0.16, 0.015, shore) * (0.30 + 0.70 * foamNoise);
    vec3 foamColor = vec3(0.72, 0.78, 0.76) * (waterIrradiance + sunColor * sunIntensity * 0.22);

    return mix(bodyLit, skyReflection, waterFresnel) + sunGlint + foamColor * foam * 0.55;
}
#endif
