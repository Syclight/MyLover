extern Image u_lowResTex;
extern Image u_historyTex;
extern vec2 u_lowResSize;
extern vec2 u_outputSize;
extern float u_historyWeight;
extern float u_sharpness;
extern float u_historyReady;
extern vec2 u_historyUvOffset;

float catmullRom(float x)
{
    x = abs(x);
    if (x > 2.0) {
        return 0.0;
    }
    if (x < 1.0) {
        return 1.5 * x * x * x - 2.5 * x * x + 1.0;
    }
    return -0.5 * x * x * x + 2.5 * x * x - 4.0 * x + 2.0;
}

vec3 sampleCatmullRom(Image tex, vec2 uv, vec2 texSize)
{
    vec2 samplePos = uv * texSize - 0.5;
    vec2 base = floor(samplePos);
    vec2 fractPos = samplePos - base;

    vec3 color = vec3(0.0);
    float totalWeight = 0.0;

    for (int y = -1; y <= 2; y++) {
        for (int x = -1; x <= 2; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 texelUv = (base + offset + 0.5) / texSize;
            float weight = catmullRom(offset.x - fractPos.x) * catmullRom(offset.y - fractPos.y);
            color += Texel(tex, texelUv).rgb * weight;
            totalWeight += weight;
        }
    }

    return color / max(totalWeight, 0.0001);
}

void sampleNeighborhood(Image tex, vec2 uv, vec2 texSize, out vec3 minimumColor, out vec3 maximumColor, out vec3 averageColor)
{
    vec2 samplePos = uv * texSize - 0.5;
    vec2 center = floor(samplePos + 0.5);

    minimumColor = vec3(10.0);
    maximumColor = vec3(-10.0);
    averageColor = vec3(0.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 texelUv = (center + vec2(float(x), float(y)) + 0.5) / texSize;
            vec3 sampleColor = Texel(tex, texelUv).rgb;
            minimumColor = min(minimumColor, sampleColor);
            maximumColor = max(maximumColor, sampleColor);
            averageColor += sampleColor;
        }
    }

    averageColor /= 9.0;
}

vec3 applySharpen(vec3 color, vec3 averageColor, float sharpness)
{
    vec3 detail = color - averageColor;
    return clamp(color + detail * sharpness, 0.0, 1.0);
}

vec4 effect(vec4 vertexColor, Image texture, vec2 textureCoords, vec2 screenCoords)
{
    vec2 uv = screenCoords / u_outputSize;

    vec3 currentColor = sampleCatmullRom(u_lowResTex, uv, u_lowResSize);

    vec3 minimumColor;
    vec3 maximumColor;
    vec3 averageColor;
    sampleNeighborhood(u_lowResTex, uv, u_lowResSize, minimumColor, maximumColor, averageColor);

    vec3 resolved = currentColor;
    if (u_historyReady > 0.5) {
        vec2 historyUv = uv + u_historyUvOffset;
        bool historyInBounds = historyUv.x >= 0.0 && historyUv.y >= 0.0 && historyUv.x <= 1.0 && historyUv.y <= 1.0;
        if (historyInBounds) {
            vec3 historyColor = Texel(u_historyTex, historyUv).rgb;
            vec3 clampedHistory = clamp(historyColor, minimumColor - 0.015, maximumColor + 0.015);
            resolved = mix(currentColor, clampedHistory, clamp(u_historyWeight, 0.0, 0.35));
        }
    }

    resolved = applySharpen(resolved, averageColor, u_sharpness);
    return vec4(resolved, 1.0) * vertexColor;
}
