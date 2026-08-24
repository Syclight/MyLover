extern vec2 u_texelSize;

float luma(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec2 rcpFrame = u_texelSize;

    vec3 rgbM = Texel(texture, texture_coords).rgb;
    vec3 rgbNW = Texel(texture, texture_coords + vec2(-rcpFrame.x, -rcpFrame.y)).rgb;
    vec3 rgbNE = Texel(texture, texture_coords + vec2(rcpFrame.x, -rcpFrame.y)).rgb;
    vec3 rgbSW = Texel(texture, texture_coords + vec2(-rcpFrame.x, rcpFrame.y)).rgb;
    vec3 rgbSE = Texel(texture, texture_coords + vec2(rcpFrame.x, rcpFrame.y)).rgb;

    float lumaM = luma(rgbM);
    float lumaNW = luma(rgbNW);
    float lumaNE = luma(rgbNE);
    float lumaSW = luma(rgbSW);
    float lumaSE = luma(rgbSE);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    if (lumaMax - lumaMin < 0.05) {
        return vec4(rgbM, 1.0) * color;
    }

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * 0.125), 0.008);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(8.0), max(vec2(-8.0), dir * rcpDirMin)) * rcpFrame;

    vec3 rgbA = 0.5 * (
        Texel(texture, texture_coords + dir * (1.0 / 3.0 - 0.5)).rgb +
        Texel(texture, texture_coords + dir * (2.0 / 3.0 - 0.5)).rgb
    );
    vec3 rgbB = rgbA * 0.5 + 0.25 * (
        Texel(texture, texture_coords + dir * -0.5).rgb +
        Texel(texture, texture_coords + dir * 0.5).rgb
    );

    float lumaB = luma(rgbB);
    if (lumaB < lumaMin || lumaB > lumaMax) {
        return vec4(rgbA, 1.0) * color;
    }

    return vec4(rgbB, 1.0) * color;
}
