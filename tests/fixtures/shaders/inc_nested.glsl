// 测试夹具：嵌套包含（且与 root 重复包含 inc_shared）
#include "inc_shared.glsl"
float nestedValue() { return sharedValue(); }
