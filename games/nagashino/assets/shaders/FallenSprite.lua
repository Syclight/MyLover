-- 贴地遗体 atlas：从俯视 sprite sheet 取格子，作为水平半透明平面渲染。
return [[
varying vec2 v_uv;
varying float v_distance;

#ifdef VERTEX
uniform mat4 u_viewProj;
uniform vec3 u_cameraPos;
attribute vec4 InstanceCenterScale;
attribute vec4 InstanceScaleRotation;
attribute vec4 InstanceUv;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float s = sin(InstanceScaleRotation.y);
    float c = cos(InstanceScaleRotation.y);
    vec2 local = vertex_position.xy;
    local = vec2(local.x * c - local.y * s, local.x * s + local.y * c);
    vec3 world = InstanceCenterScale.xyz;
    world.x += local.x * InstanceCenterScale.w;
    world.z += local.y * InstanceScaleRotation.x;
    v_uv = vec2(mix(InstanceScaleRotation.z, InstanceScaleRotation.w, VertexTexCoord.x),
        mix(InstanceUv.x, InstanceUv.y, VertexTexCoord.y));
    v_distance = length(u_cameraPos - world);
    return u_viewProj * vec4(world, 1.0);
}
#endif

#ifdef PIXEL
uniform vec3 u_fogColor;
uniform float u_fogStart;
uniform float u_fogDensity;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 albedo = Texel(tex, v_uv) * color;
    if (albedo.a < 0.10) discard;
    float fogDistance = max(v_distance - u_fogStart, 0.0);
    float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogDensity * u_fogDensity);
    albedo.rgb = mix(albedo.rgb, u_fogColor, clamp(fog, 0.0, 1.0));
    return albedo;
}
#endif
]]
