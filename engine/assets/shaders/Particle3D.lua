-- 通用 3D 粒子 billboard：颜色、尺寸和旋转均由实例缓冲提供。
return [[
varying vec2 v_uv;
varying vec4 v_color;
varying float v_distance;

#ifdef VERTEX
uniform mat4 u_viewProj;
uniform vec3 u_cameraPos;
uniform vec3 u_cameraRight;
uniform vec3 u_cameraUp;
attribute vec4 InstanceCenterSize;
attribute vec4 InstanceColor;
attribute float InstanceRotation;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float s = sin(InstanceRotation);
    float c = cos(InstanceRotation);
    vec2 local = vertex_position.xy;
    local = vec2(local.x * c - local.y * s, local.x * s + local.y * c);
    vec3 world = InstanceCenterSize.xyz
        + u_cameraRight * (local.x * InstanceCenterSize.w)
        + u_cameraUp * (local.y * InstanceCenterSize.w);
    v_uv = VertexTexCoord.xy;
    v_color = InstanceColor;
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
    vec4 noise = Texel(tex, v_uv);
    // 使用任意灰度噪声图时仍能得到圆润的透明边缘，避免 billboard 显出方形底。
    float edge = 1.0 - smoothstep(0.20, 0.71, length(v_uv - vec2(0.5)));
    vec4 particle = vec4(noise.rgb * color.rgb * v_color.rgb, color.a * v_color.a);
    particle.a *= edge * mix(0.62, 1.0, noise.r);
    if (particle.a < 0.008) discard;
    float fogDistance = max(v_distance - u_fogStart, 0.0);
    float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogDensity * u_fogDensity);
    particle.rgb = mix(particle.rgb, u_fogColor, clamp(fog, 0.0, 1.0));
    return particle;
}
#endif
]]
