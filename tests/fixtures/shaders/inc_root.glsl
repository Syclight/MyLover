// 测试夹具：根文件，直接包含 shared，又经 nested 间接包含 shared
#include "inc_shared.glsl"
#include "inc_nested.glsl"
vec2 rootValues() { return vec2(sharedValue(), nestedValue()); }
