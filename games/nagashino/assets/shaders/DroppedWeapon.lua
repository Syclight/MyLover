-- 低面数落地武器：以实例化小盒表现枪、矛和刀，不为每具遗体新增独立模型。
return [[
varying vec2 v_uv;
varying float v_type;
varying float v_light;
varying float v_distance;

#ifdef VERTEX
uniform mat4 u_viewProj;
uniform vec3 u_cameraPos;
attribute vec4 InstanceCenterLength;
attribute vec4 InstanceWeaponShape;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float angle = InstanceWeaponShape.y;
    float s = sin(angle);
    float c = cos(angle);
    vec3 local = vertex_position.xyz;
    local.x *= InstanceCenterLength.w;
    local.z *= InstanceWeaponShape.x;
    vec3 world = InstanceCenterLength.xyz;
    world.x += local.x * c - local.z * s;
    world.z += local.x * s + local.z * c;
    world.y += local.y;
    // 无纹理几何不会在所有驱动上声明 VertexTexCoord；局部坐标足以生成木/铁色变化。
    v_uv = vec2(vertex_position.x + 0.5, vertex_position.z + 0.5);
    v_type = InstanceWeaponShape.z;
    // This tiny prop has no normal attribute on all supported drivers.
    v_light = 0.76;
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
    float metal = v_type < 0.5 ? smoothstep(0.70, 1.0, v_uv.x) : 0.0;
    if (v_type > 1.5) metal = smoothstep(0.78, 1.0, v_uv.x) * 0.72;
    vec3 wood = mix(vec3(0.18, 0.095, 0.040), vec3(0.42, 0.22, 0.095), v_uv.y);
    vec3 iron = vec3(0.23, 0.25, 0.25);
    vec3 surface = mix(wood, iron, metal) * v_light;
    float fogDistance = max(v_distance - u_fogStart, 0.0);
    float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogDensity * u_fogDensity);
    return vec4(mix(surface, u_fogColor, clamp(fog, 0.0, 1.0)), 1.0);
}
#endif
]]
