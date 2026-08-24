return [[
#ifdef PIXEL
uniform vec2 u_resolution;
uniform vec3 u_viewForward;
uniform vec3 u_viewRight;
uniform vec3 u_viewUp;
uniform vec3 u_sunDir;
uniform vec3 u_sunColor;
uniform vec3 u_skyTop;
uniform vec3 u_skyHorizon;
uniform vec3 u_groundHaze;
uniform float u_tanHalfFov;
uniform float u_aspect;
uniform float u_time;
uniform float u_exposure;
uniform float u_cloudCoverage;
uniform float u_cloudScale;
uniform float u_cloudSpeed;
uniform float u_hasSkyTexture;
uniform float u_skyRotation;
uniform Image u_skyTexture;

float hash21(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p)
{
    float sum = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        sum += valueNoise(p) * amplitude;
        p = p * 2.03 + vec2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return sum;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screenCoords)
{
    vec2 ndc = screenCoords / u_resolution * 2.0 - 1.0;
    ndc.y = -ndc.y;
    vec3 ray = normalize(u_viewForward
        + u_viewRight * ndc.x * u_aspect * u_tanHalfFov
        + u_viewUp * ndc.y * u_tanHalfFov);
    vec3 sunDir = normalize(u_sunDir);

    float elevation = clamp(ray.y, 0.0, 1.0);
    float horizon = exp(-elevation * 6.5);
    float sunAmount = max(dot(ray, sunDir), 0.0);
    float rayleighPhase = 0.75 * (1.0 + sunAmount * sunAmount);
    float mieHalo = pow(sunAmount, 18.0) * 0.38 + pow(sunAmount, 96.0) * 1.15;

    vec3 sky = mix(u_skyHorizon, u_skyTop, pow(elevation, 0.42));
    float phaseBlend = smoothstep(0.025, 0.35, elevation);
    float phaseModulation = mix(1.0, mix(1.08, 0.78, elevation) * rayleighPhase, phaseBlend);
    sky *= phaseModulation;
    sky += u_sunColor * mieHalo * mix(1.0, 0.35, elevation);

    float sunDisc = smoothstep(0.99978, 0.99994, sunAmount);
    sky += u_sunColor * sunDisc * 8.0;

    if (u_hasSkyTexture > 0.5) {
        float longitude = atan(ray.z, ray.x) / 6.28318530718 + 0.5 + u_skyRotation;
        float latitude = 0.5 - asin(clamp(ray.y, -1.0, 1.0)) / 3.14159265359;
        vec3 photographedSky = Texel(u_skyTexture,
            vec2(fract(longitude), clamp(latitude, 0.0, 1.0))).rgb;
        float photoBlend = smoothstep(0.0, 0.07, ray.y) * 0.94;
        sky = mix(sky, photographedSky, photoBlend);
    } else if (ray.y > 0.015) {
        vec2 cloudUv = ray.xz / (ray.y + 0.16) * u_cloudScale;
        cloudUv += vec2(u_time * u_cloudSpeed, u_time * u_cloudSpeed * 0.27);
        float cloudNoise = fbm(cloudUv);
        float cloud = smoothstep(u_cloudCoverage, u_cloudCoverage + 0.13, cloudNoise);
        float cloudFade = smoothstep(0.015, 0.12, ray.y) * (1.0 - smoothstep(0.45, 0.98, ray.y));
        float cloudSun = pow(max(dot(normalize(vec3(ray.x, 0.35, ray.z)), sunDir), 0.0), 5.0);
        vec3 cloudShade = mix(vec3(0.58, 0.64, 0.70), vec3(1.0, 0.96, 0.86), 0.55 + cloudSun * 0.45);
        sky = mix(sky, cloudShade, cloud * cloudFade * 0.78);
    }

    float belowHorizon = 1.0 - smoothstep(-0.18, -0.02, ray.y);
    vec3 groundSky = mix(u_skyHorizon, u_groundHaze, belowHorizon);
    sky = mix(sky, groundSky, belowHorizon);
    sky += u_sunColor * horizon * pow(sunAmount, 8.0) * 0.16;

    float exposure = u_exposure > 0.0 ? u_exposure : 1.0;
    sky = vec3(1.0) - exp(-max(sky, vec3(0.0)) * exposure);
    return vec4(sky, 1.0) * color;
}
#endif
]]
