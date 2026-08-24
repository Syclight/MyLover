-- 遗体半胶囊：顶面采样死亡图集，薄端盖使用图集扩散色，不产生黑色围边。
return [[
varying vec3 v_normal;
varying vec3 v_worldPos;
varying vec2 v_uv;
varying float v_side;
#ifdef VERTEX
uniform mat4 u_viewProj;
uniform vec3 u_cameraPos;
attribute vec3 VertexNormal;
attribute vec4 InstanceCenterScale;
attribute vec4 InstanceScaleRotation;
attribute vec4 InstanceUv;
attribute float VertexSide;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float s = sin(InstanceScaleRotation.y);
    float c = cos(InstanceScaleRotation.y);
    float width = InstanceCenterScale.w;
    float length = InstanceScaleRotation.x;
    vec3 world = InstanceCenterScale.xyz;
    world.x += (vertex_position.x * c - vertex_position.z * s) * width;
    world.z += (vertex_position.x * s + vertex_position.z * c) * length;
    world.y += vertex_position.y * max(width, length);
    v_worldPos = world;
    v_normal = normalize(vec3(
        VertexNormal.x * c - VertexNormal.z * s,
        VertexNormal.y,
        VertexNormal.x * s + VertexNormal.z * c));
    v_uv = vec2(mix(InstanceScaleRotation.z, InstanceScaleRotation.w, VertexTexCoord.x),
        mix(InstanceUv.x, InstanceUv.y, VertexTexCoord.y));
    v_side = VertexSide;
    return u_viewProj * vec4(world, 1.0);
}
#endif
#ifdef PIXEL
uniform vec3 u_lightDir;
uniform vec3 u_fogColor;
uniform Image u_edgeTexture;
uniform float u_fogStart;
uniform float u_fogDensity;
uniform vec3 u_cameraPos;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 albedo = Texel(tex, v_uv) * color;
    vec3 edgeColor = Texel(u_edgeTexture, v_uv).rgb;
    float diffuse = max(dot(normalize(v_normal), normalize(u_lightDir)), 0.0);
    if (v_side < 0.5 && albedo.a < 0.10) discard;
    vec3 surface = v_side < 0.5 ? albedo.rgb : edgeColor * 0.52;
    vec3 lit = surface * (0.32 + diffuse * 0.68);
    float d = max(length(u_cameraPos - v_worldPos) - u_fogStart, 0.0);
    float fog = 1.0 - exp(-d * d * u_fogDensity * u_fogDensity);
    return vec4(mix(lit, u_fogColor, clamp(fog, 0.0, 1.0)), v_side < 0.5 ? albedo.a : 0.76);
}
#endif
]]
