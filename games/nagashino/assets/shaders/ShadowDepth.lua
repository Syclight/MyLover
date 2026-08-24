-- 方向光 shadow map：将深度编码到颜色通道，兼容不支持可采样 depth Canvas 的设备。
return [[
varying vec2 v_uv;

#ifdef VERTEX
uniform mat4 u_model;
uniform mat4 u_lightViewProj;

vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    v_uv = VertexTexCoord.xy;
    return u_lightViewProj * u_model * vertex_position;
}
#endif

#ifdef PIXEL
uniform float u_hasAlphaMask;
uniform float u_alphaCutoff;
uniform Image u_alphaMask;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    float alpha = Texel(tex, uv).a;
    if (u_hasAlphaMask > 0.5) alpha *= Texel(u_alphaMask, uv).r;
    if (alpha < u_alphaCutoff) discard;
    return vec4(vec3(gl_FragCoord.z), 1.0);
}
#endif
]]
