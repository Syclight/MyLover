-- 实例化 HD-2D 角色：不走 PBR/PCF 阴影，只保留贴图、色调和距离雾。
return [[
varying vec2 v_uv;
varying float v_distance;

#ifdef VERTEX
uniform mat4 u_viewProj;
uniform vec3 u_cameraPos;
attribute vec4 InstanceCenter;
attribute vec4 InstanceRightSize;
attribute vec4 InstanceUv;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec3 right = vec3(InstanceRightSize.x, 0.0, InstanceRightSize.y);
    vec3 world = InstanceCenter.xyz + right * (vertex_position.x * InstanceRightSize.z);
    world.y += vertex_position.y * InstanceRightSize.w;
    v_uv = vec2(mix(InstanceUv.x, InstanceUv.y, VertexTexCoord.x),
        mix(InstanceUv.z, InstanceUv.w, VertexTexCoord.y));
    v_distance = length(u_cameraPos - world);
    return u_viewProj * vec4(world, 1.0);
}
#endif

#ifdef PIXEL
uniform vec4 u_tint;
uniform vec3 u_fogColor;
uniform float u_fogStart;
uniform float u_fogDensity;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 albedo = Texel(tex, v_uv) * color * u_tint;
    if (albedo.a < 0.12) discard;
    float fogDistance = max(v_distance - u_fogStart, 0.0);
    float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogDensity * u_fogDensity);
    albedo.rgb = mix(albedo.rgb, u_fogColor, clamp(fog, 0.0, 1.0));
    return albedo;
}
#endif
]]
