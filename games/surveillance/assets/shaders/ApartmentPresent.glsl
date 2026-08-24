extern vec2 u_texelSize;
extern float u_fxaaEnabled;
extern float u_drowsiness;

float luma(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 applyFxaa(Image texture, vec2 uv)
{
    vec3 rgbM = Texel(texture, uv).rgb;
    if (u_fxaaEnabled < 0.5) return rgbM;
    vec3 rgbNW = Texel(texture, uv + vec2(-u_texelSize.x, -u_texelSize.y)).rgb;
    vec3 rgbNE = Texel(texture, uv + vec2( u_texelSize.x, -u_texelSize.y)).rgb;
    vec3 rgbSW = Texel(texture, uv + vec2(-u_texelSize.x,  u_texelSize.y)).rgb;
    vec3 rgbSE = Texel(texture, uv + vec2( u_texelSize.x,  u_texelSize.y)).rgb;
    float lumaM = luma(rgbM);
    float lumaNW = luma(rgbNW);
    float lumaNE = luma(rgbNE);
    float lumaSW = luma(rgbSW);
    float lumaSE = luma(rgbSE);
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    if (lumaMax - lumaMin < 0.05) return rgbM;
    vec2 dir = vec2(-((lumaNW + lumaNE) - (lumaSW + lumaSE)),
        (lumaNW + lumaSW) - (lumaNE + lumaSE));
    float reduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.03125, 0.008);
    dir = clamp(dir / (min(abs(dir.x), abs(dir.y)) + reduce), vec2(-8.0), vec2(8.0)) * u_texelSize;
    vec3 rgbA = 0.5 * (Texel(texture, uv + dir * -0.1666667).rgb
        + Texel(texture, uv + dir * 0.1666667).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (Texel(texture, uv + dir * -0.5).rgb
        + Texel(texture, uv + dir * 0.5).rgb);
    float lumaB = luma(rgbB);
    return (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;
}

vec3 drowsyBlur(Image texture, vec2 uv, float strength)
{
    vec2 radius = u_texelSize * (2.0 + strength * 8.0);
    vec3 sum = Texel(texture, uv).rgb * 0.20;
    sum += Texel(texture, uv + vec2( radius.x, 0.0)).rgb * 0.10;
    sum += Texel(texture, uv + vec2(-radius.x, 0.0)).rgb * 0.10;
    sum += Texel(texture, uv + vec2(0.0,  radius.y)).rgb * 0.10;
    sum += Texel(texture, uv + vec2(0.0, -radius.y)).rgb * 0.10;
    vec2 diagonal = radius * 0.70710678;
    sum += Texel(texture, uv + vec2( diagonal.x,  diagonal.y)).rgb * 0.10;
    sum += Texel(texture, uv + vec2(-diagonal.x,  diagonal.y)).rgb * 0.10;
    sum += Texel(texture, uv + vec2( diagonal.x, -diagonal.y)).rgb * 0.10;
    sum += Texel(texture, uv + vec2(-diagonal.x, -diagonal.y)).rgb * 0.10;
    return sum;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    float strength = clamp(u_drowsiness, 0.0, 1.0);
    vec3 sharp = applyFxaa(texture, texture_coords);
    if (strength <= 0.001) return vec4(sharp, 1.0) * color;
    vec3 blurred = drowsyBlur(texture, texture_coords, strength);
    float blend = smoothstep(0.0, 1.0, strength) * 0.94;
    vec3 result = mix(sharp, blurred, blend);
    float edge = smoothstep(0.28, 0.72, length(texture_coords - vec2(0.5)));
    result *= 1.0 - edge * strength * 0.10;
    return vec4(result, 1.0) * color;
}
