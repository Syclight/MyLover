-- 实例化贴地阴影：独立于环境 PBR 和 shadow map，避免无意义的 PCF 采样。
return [[
varying vec2 v_shape;
varying float v_alpha;

#ifdef VERTEX
uniform mat4 u_viewProj;
attribute vec4 InstanceShadowCenter;
attribute vec4 InstanceShadowScale;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec3 world = InstanceShadowCenter.xyz;
    world.x += vertex_position.x * InstanceShadowCenter.w;
    world.z += vertex_position.y * InstanceShadowScale.x;
    v_shape = vertex_position.xy;
    v_alpha = InstanceShadowScale.y;
    return u_viewProj * vec4(world, 1.0);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    float radius = length(v_shape);
    float alpha = (1.0 - smoothstep(0.42, 1.0, radius)) * v_alpha;
    return vec4(0.012, 0.010, 0.008, alpha);
}
#endif
]]
