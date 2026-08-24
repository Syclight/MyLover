// 通用光照函数库（经 ShaderPreprocessor 的 #include 引用，不单独编译）。
// 约定：所有向量在同一空间（本工程为世界空间）；lightDir 指向光源、已归一化。

// 兰伯特方向光：环境光 + 漫反射。normal 在此归一化，调用方无需预处理。
vec3 lambertLight(vec3 albedo, vec3 normal, vec3 lightDir, vec3 ambient)
{
    float diff = max(dot(normalize(normal), lightDir), 0.0);
    return albedo * (ambient + vec3(diff));
}
