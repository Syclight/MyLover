-- 持久地面弹坑 decal：浅盆地几何 + 土壤材质，不依赖地形真实位移。
return [[
varying vec2 v_uv;
varying vec2 v_detailUv;
varying float v_radius;
varying vec3 v_worldPos;
varying float v_strength;
#ifdef VERTEX
uniform mat4 u_viewProj;
attribute vec4 InstanceCenterScale;
attribute vec4 InstanceShape;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float s = sin(InstanceShape.y);
    float c = cos(InstanceShape.y);
    vec3 world = InstanceCenterScale.xyz;
    world.x += vertex_position.x * c * InstanceCenterScale.w - vertex_position.z * s * InstanceShape.x;
    world.z += vertex_position.x * s * InstanceCenterScale.w + vertex_position.z * c * InstanceShape.x;
    world.y += vertex_position.y * max(InstanceCenterScale.w, InstanceShape.x);
    v_worldPos = world;
    v_uv = VertexTexCoord.xy;
    v_detailUv = world.xz * 0.58 + vec2(InstanceShape.z, InstanceShape.z * 0.67);
    v_radius = length(vertex_position.xz);
    v_strength = InstanceShape.w;
    return u_viewProj * vec4(world, 1.0);
}
#endif
#ifdef PIXEL
uniform Image u_dirtTexture;
uniform vec3 u_fogColor;
uniform vec3 u_cameraPos;
uniform float u_fogStart;
uniform float u_fogDensity;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    if (v_radius > 1.0) discard;
    vec3 dirt = Texel(u_dirtTexture, v_detailUv).rgb;
    float basin = 1.0 - smoothstep(0.12, 0.78, v_radius);
    float rim = smoothstep(0.68, 0.90, v_radius) * (1.0 - smoothstep(0.90, 1.0, v_radius));
    vec3 shaded = dirt * (0.42 + rim * 0.28 + (1.0 - basin) * 0.08) * v_strength;
    float alpha = smoothstep(1.0, 0.78, v_radius) * 0.82 * v_strength;
    float distance = max(length(u_cameraPos - v_worldPos), 0.0);
    float fog = clamp((distance - u_fogStart) * u_fogDensity * 0.02, 0.0, 0.32);
    return vec4(mix(shaded, u_fogColor, fog), alpha);
}
#endif
]]
