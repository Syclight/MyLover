// samples/raycast/assets/shaders/SpriteGBuffer.glsl
extern Image u_spriteTex;
extern vec3 u_normal;
extern float u_depth;
extern float u_maxDepth;

void effect() {
    vec4 texColor = Texel(u_spriteTex, VaryingTexCoord.xy);
    if (texColor.a < 0.1) discard; // 剔除透明部分

    vec4 albedo = VaryingColor * texColor;
    vec3 encodedNormal = u_normal * 0.5 + 0.5;
    float encodedDepth = clamp(u_depth / u_maxDepth, 0.0, 1.0);

    love_Canvases[0] = albedo;
    love_Canvases[1] = vec4(encodedNormal, 1.0);
    love_Canvases[2] = vec4(encodedDepth, encodedDepth, encodedDepth, 1.0);
}
