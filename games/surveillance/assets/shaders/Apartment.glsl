// Apartment.glsl — 公寓场景专用光投着色器。
// 由 ShaderMaze.glsl 派生（不修改原文件），额外渲染写实的"计算机"与"椅子"
// （与桌子一样用解析 AABB 几何），并让显示器屏幕自发光（材质 6）。
extern Image u_mapTex;
extern vec2 u_mapSize;
extern vec2 u_mapOrigin;
extern vec2 u_worldMapSize;
extern float u_tileSize;
extern vec2 u_renderSize;
extern vec2 u_jitter;
extern vec2 u_playerPos;
extern float u_playerHeight;
extern vec3 u_cameraForward;
extern vec3 u_cameraRight;
extern vec3 u_cameraUp;
extern float u_tanHalfFov;
extern float u_invAspect;
extern float u_wallMaxHeight;
extern float u_ceilingHeight;

extern vec2 u_tablePos;
extern vec2 u_tableSize;
extern float u_tableTopHeight;
extern float u_tableThickness;
extern float u_tableLegThickness;
extern vec3 u_tableColor;

extern vec2 u_pyramidPos;
extern float u_pyramidSize;
extern float u_pyramidHeight;
extern vec3 u_pyramidColor;

// 新增：计算机 / 椅子
extern vec2 u_computerPos;
extern float u_computerPresent;
extern vec2 u_chairPos;
extern float u_chairPresent;

// 空调（挂墙）+ 桌面遥控器
extern vec2 u_acPos;            // (中心 x, 贴墙的 y 面)，单位米
extern float u_acPresent;
extern float u_acTopHeight;     // 空调顶部高度（米）
extern float u_acState;         // 0=关 1=制冷 2=制热
extern vec2 u_remotePos;        // 桌面遥控器位置（米）
extern float u_remotePresent;   // 被拿起时为 0（不渲染）
extern float u_remoteTopHeight; // 遥控器所在桌面高度（米）
extern vec3 u_clockPos;          // 挂钟中心 (x, 墙面y, 高度)，单位米
extern float u_clockPresent;
extern vec2 u_clockHourHand;     // 表盘方向：(右, 上)
extern vec2 u_clockMinuteHand;
extern vec3 u_calendarPos;
extern float u_calendarPresent;
extern float u_calendarFacing;   // +1 北墙朝南，-1 南墙朝北
extern Image u_calendarTex;
extern Image u_materialAtlas;

// 通用写实家具实例：vec4 = (worldX, worldY, type, yawRad)
// type: 1=床 2=沙发 3=书架 4=柜子 6=吊灯
extern int u_furnitureCount;
extern vec4 u_furniture0;
extern vec4 u_furniture1;
extern vec4 u_furniture2;
extern vec4 u_furniture3;
extern vec4 u_furniture4;
extern vec4 u_furniture5;
extern vec4 u_furniture6;
extern vec4 u_furniture7;
extern float u_bookshelfMaskLeft;
extern float u_bookshelfMaskRight;
extern float u_bookshelfBookStylesLeft;
extern float u_bookshelfBookStylesRight;
extern vec3 u_bookColor1;
extern vec3 u_bookColor2;
extern vec3 u_bookColor3;
extern vec3 u_bookColor4;
extern vec3 u_bookColor5;
extern vec3 u_bookColor6;
extern int u_placedBookCount;
extern vec4 u_placedBook0;
extern vec4 u_placedBook1;
extern vec4 u_placedBook2;
extern vec4 u_placedBook3;
extern vec4 u_placedBook4;
extern vec4 u_placedBook5;
extern vec4 u_placedBook6;
extern vec4 u_placedBook7;
extern vec4 u_placedBook8;
extern vec4 u_placedBook9;
extern vec4 u_placedBook10;
extern vec4 u_placedBook11;
extern vec4 u_bookPreview;

extern int u_pointLightCount;
extern vec3 u_pointLightPos0;
extern vec3 u_pointLightPos1;
extern vec3 u_pointLightPos2;
extern vec3 u_pointLightPos3;
extern vec3 u_pointLightPos4;
extern vec3 u_pointLightPos5;
extern vec3 u_pointLightColor0;
extern vec3 u_pointLightColor1;
extern vec3 u_pointLightColor2;
extern vec3 u_pointLightColor3;
extern vec3 u_pointLightColor4;
extern vec3 u_pointLightColor5;
extern vec2 u_pointLightParams0;
extern vec2 u_pointLightParams1;
extern vec2 u_pointLightParams2;
extern vec2 u_pointLightParams3;
extern vec2 u_pointLightParams4;
extern vec2 u_pointLightParams5;

const float FAR_CLIP = 40.0;
const float INF = 1.0e20;
const float EPSILON = 0.0001;
const int MAX_DDA_STEPS = 192;
const int MAX_POINT_LIGHTS = 6;
const vec2 MATERIAL_ATLAS_GRID = vec2(4.0, 2.0);
const float MAT_WALL = 1.0;
const float MAT_WOOD = 2.0;
const float MAT_PLASTIC = 3.0;
const float MAT_FLOOR = 4.0;
const float MAT_CEILING = 5.0;
const float MAT_EMISSIVE = 6.0;
const float MAT_VINYL = 7.0;
const float MAT_PAPER = 8.0;
const float MAT_FABRIC = 9.0;

float saturate(float x)
{
    return clamp(x, 0.0, 1.0);
}

float hash21(vec2 p)
{
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float luminance(vec3 color)
{
    return dot(color, vec3(0.299, 0.587, 0.114));
}

float materialAtlasTile(vec3 albedo, float materialId)
{
    if (materialId > 0.5 && materialId < 1.5) return 0.0; // aged plaster wall
    if (materialId > 1.5 && materialId < 2.5) return 1.0; // dark worn wood
    if (materialId > 2.5 && materialId < 3.5) return 2.0; // matte black plastic
    if (materialId > 3.5 && materialId < 4.5) return 3.0; // scuffed linoleum
    if (materialId > 4.5 && materialId < 5.5) return 4.0; // smoky ceiling paint
    if (materialId > 6.5 && materialId < 7.5) return 5.0; // brown vinyl/leather
    if (materialId > 7.5 && materialId < 8.5) return 6.0; // off-white plastic/paper
    if (materialId > 8.5 && materialId < 9.5) return 7.0; // muted fabric

    if (albedo.r > 0.82 && albedo.g > 0.82 && albedo.b > 0.76) return 6.0; // off-white plastic/paper
    if (albedo.b > albedo.r * 1.08 && albedo.b > albedo.g * 0.90) return 7.0; // fabric weave
    if (albedo.r < 0.18 && albedo.g < 0.18 && albedo.b < 0.20) return 2.0; // matte black plastic
    if (albedo.r > albedo.b * 1.25 && albedo.g > albedo.b * 0.80) return 1.0; // dark worn wood
    return 5.0; // brown vinyl/leather
}

vec3 sampleMaterialAtlas(float tileIndex, vec2 uv)
{
    float tx = mod(tileIndex, MATERIAL_ATLAS_GRID.x);
    float ty = floor(tileIndex / MATERIAL_ATLAS_GRID.x);
    vec2 cellUv = fract(uv) * 0.94 + 0.03;
    return Texel(u_materialAtlas, (vec2(tx, ty) + cellUv) / MATERIAL_ATLAS_GRID).rgb;
}

vec3 materialDetail(vec3 pos, vec3 normal, vec3 albedo, float materialId)
{
    vec2 uv = abs(normal.z) > 0.65 ? pos.xy : (abs(normal.x) > abs(normal.y) ? pos.yz : pos.xz);
    float tile = materialAtlasTile(albedo, materialId);
    float textureScale = (materialId > 3.5 && materialId < 4.5) ? 1.25
        : ((materialId > 4.5 && materialId < 5.5) ? 0.95
        : ((materialId > 8.5 && materialId < 9.5) ? 2.05 : 1.55));
    vec3 atlas = sampleMaterialAtlas(tile, uv * textureScale);
    float atlasLuma = clamp(luminance(atlas), 0.08, 0.95);
    vec3 atlasChroma = atlas / atlasLuma;
    float atlasStrength = (materialId > 0.5 && materialId < 1.5) ? 0.62
        : ((materialId > 3.5 && materialId < 4.5) ? 0.76
        : ((materialId > 8.5 && materialId < 9.5) ? 0.70 : 0.64));
    vec3 textured = albedo * mix(0.58, 1.34, atlasLuma);
    textured = mix(textured, albedo * atlasChroma, 0.28);
    textured *= 1.0 + (atlasLuma - 0.5) * 0.32;
    albedo = mix(albedo, clamp(textured, 0.0, 1.2), atlasStrength);

    float n1 = valueNoise(uv * 18.0);
    float n2 = valueNoise(uv * 5.0 + 7.1);
    float grain = (n1 - 0.5) * 0.045 + (n2 - 0.5) * 0.028;
    if (materialId > 3.5 && materialId < 4.5) {
        grain *= 0.55;
    } else if (materialId > 4.5 && materialId < 5.5) {
        grain *= 0.35;
    }
    return clamp(albedo * (1.0 + grain), 0.0, 1.2);
}

vec3 skyColor(vec3 rd)
{
    float t = saturate(0.5 + rd.z * 0.5);
    vec3 horizon = vec3(0.70, 0.67, 0.58);
    vec3 zenith = vec3(0.24, 0.34, 0.47);
    vec3 groundGlow = vec3(0.43, 0.36, 0.28);

    if (rd.z < 0.0) {
        float g = saturate(-rd.z);
        return mix(horizon, groundGlow, g);
    }

    return mix(horizon, zenith, t);
}

bool sampleWall(vec2 cell, out vec3 albedo, out float wallHeight)
{
    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= u_worldMapSize.x || cell.y >= u_worldMapSize.y) {
        albedo = vec3(0.16, 0.14, 0.13);
        wallHeight = u_wallMaxHeight;
        return true;
    }

    vec2 localCell = floor(cell) - u_mapOrigin;
    if (localCell.x < 0.0 || localCell.y < 0.0 || localCell.x >= u_mapSize.x || localCell.y >= u_mapSize.y) {
        albedo = vec3(0.16, 0.14, 0.13);
        wallHeight = u_wallMaxHeight;
        return true;
    }

    vec2 uv = (localCell + 0.5) / u_mapSize;
    vec4 data = Texel(u_mapTex, uv);
    albedo = data.rgb;
    wallHeight = data.a * u_wallMaxHeight;
    return data.a > 0.001;
}

bool sampleWallShadow(vec2 cell, out float wallHeight)
{
    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= u_worldMapSize.x || cell.y >= u_worldMapSize.y) {
        wallHeight = 0.0;
        return false;
    }

    vec2 localCell = floor(cell) - u_mapOrigin;
    if (localCell.x < 0.0 || localCell.y < 0.0 || localCell.x >= u_mapSize.x || localCell.y >= u_mapSize.y) {
        wallHeight = 0.0;
        return false;
    }

    vec2 uv = (localCell + 0.5) / u_mapSize;
    vec4 data = Texel(u_mapTex, uv);
    wallHeight = data.a * u_wallMaxHeight;
    return data.a > 0.001;
}

bool intersectAABB(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax, out float tHit, out vec3 normal)
{
    vec3 invDir = vec3(
        (abs(rd.x) < EPSILON) ? INF : (1.0 / rd.x),
        (abs(rd.y) < EPSILON) ? INF : (1.0 / rd.y),
        (abs(rd.z) < EPSILON) ? INF : (1.0 / rd.z)
    );
    vec3 t0 = (bmin - ro) * invDir;
    vec3 t1 = (bmax - ro) * invDir;
    vec3 tmin3 = min(t0, t1);
    vec3 tmax3 = max(t0, t1);

    float tNear = max(max(tmin3.x, tmin3.y), tmin3.z);
    float tFar = min(min(tmax3.x, tmax3.y), tmax3.z);
    if (tFar < max(tNear, 0.0)) {
        return false;
    }

    tHit = (tNear > 0.0) ? tNear : tFar;
    vec3 hitPos = ro + rd * tHit;
    vec3 center = (bmin + bmax) * 0.5;
    vec3 extent = max((bmax - bmin) * 0.5, vec3(EPSILON));
    vec3 local = (hitPos - center) / extent;
    vec3 absLocal = abs(local);

    if (absLocal.x > absLocal.y && absLocal.x > absLocal.z) {
        normal = vec3(sign(local.x), 0.0, 0.0);
    } else if (absLocal.y > absLocal.z) {
        normal = vec3(0.0, sign(local.y), 0.0);
    } else {
        normal = vec3(0.0, 0.0, sign(local.z));
    }

    return true;
}

// 测试一个盒子并更新最近命中（带 albedo / material）
void hitBox(vec3 ro, vec3 rd, vec3 bmin, vec3 bmax, vec3 boxAlbedo, float boxMat,
    inout float tHit, inout vec3 normal, inout vec3 albedo, inout float material)
{
    float ct;
    vec3 cn;
    if (intersectAABB(ro, rd, bmin, bmax, ct, cn) && ct > EPSILON && ct < tHit) {
        tHit = ct;
        normal = cn;
        albedo = boxAlbedo;
        material = boxMat;
    }
}

bool intersectTriangle(vec3 ro, vec3 rd, vec3 v0, vec3 v1, vec3 v2, out float tHit, out vec3 normal)
{
    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 pvec = cross(rd, edge2);
    float det = dot(edge1, pvec);

    if (abs(det) < EPSILON) {
        return false;
    }

    float invDet = 1.0 / det;
    vec3 tvec = ro - v0;
    float u = dot(tvec, pvec) * invDet;
    if (u < 0.0 || u > 1.0) {
        return false;
    }

    vec3 qvec = cross(tvec, edge1);
    float v = dot(rd, qvec) * invDet;
    if (v < 0.0 || (u + v) > 1.0) {
        return false;
    }

    float t = dot(edge2, qvec) * invDet;
    if (t <= EPSILON) {
        return false;
    }

    tHit = t;
    normal = normalize(cross(edge1, edge2));
    if (dot(normal, rd) > 0.0) {
        normal = -normal;
    }
    return true;
}

void updateNearestHit(
    float candidateT,
    vec3 candidateNormal,
    vec3 candidateAlbedo,
    float candidateMaterial,
    inout float bestT,
    inout vec3 bestNormal,
    inout vec3 bestAlbedo,
    inout float bestMaterial
)
{
    if (candidateT > EPSILON && candidateT < bestT) {
        bestT = candidateT;
        bestNormal = candidateNormal;
        bestAlbedo = candidateAlbedo;
        bestMaterial = candidateMaterial;
    }
}

bool intersectTable(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo)
{
    tHit = INF;
    albedo = u_tableColor;
    normal = vec3(0.0, 0.0, 1.0);

    float halfWidth = u_tableSize.x * 0.5;
    float halfDepth = u_tableSize.y * 0.5;
    float leg = u_tableLegThickness * 0.5;
    float legTop = max(0.0, u_tableTopHeight - u_tableThickness);
    float candidateT;
    vec3 candidateNormal;

    if (intersectAABB(
        ro,
        rd,
        vec3(u_tablePos.x - halfWidth, u_tablePos.y - halfDepth, legTop),
        vec3(u_tablePos.x + halfWidth, u_tablePos.y + halfDepth, u_tableTopHeight),
        candidateT,
        candidateNormal
    )) {
        tHit = candidateT;
        normal = candidateNormal;
    }

    vec2 corner0 = vec2(u_tablePos.x - halfWidth + leg, u_tablePos.y - halfDepth + leg);
    vec2 corner1 = vec2(u_tablePos.x + halfWidth - leg, u_tablePos.y - halfDepth + leg);
    vec2 corner2 = vec2(u_tablePos.x - halfWidth + leg, u_tablePos.y + halfDepth - leg);
    vec2 corner3 = vec2(u_tablePos.x + halfWidth - leg, u_tablePos.y + halfDepth - leg);

    if (intersectAABB(ro, rd, vec3(corner0.x - leg, corner0.y - leg, 0.0), vec3(corner0.x + leg, corner0.y + leg, legTop), candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectAABB(ro, rd, vec3(corner1.x - leg, corner1.y - leg, 0.0), vec3(corner1.x + leg, corner1.y + leg, legTop), candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectAABB(ro, rd, vec3(corner2.x - leg, corner2.y - leg, 0.0), vec3(corner2.x + leg, corner2.y + leg, legTop), candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectAABB(ro, rd, vec3(corner3.x - leg, corner3.y - leg, 0.0), vec3(corner3.x + leg, corner3.y + leg, legTop), candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }

    return tHit < INF;
}

bool intersectPyramid(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo)
{
    float halfSize = u_pyramidSize * 0.5;
    float baseZ = u_tableTopHeight;
    vec3 p0 = vec3(u_pyramidPos.x - halfSize, u_pyramidPos.y - halfSize, baseZ);
    vec3 p1 = vec3(u_pyramidPos.x + halfSize, u_pyramidPos.y - halfSize, baseZ);
    vec3 p2 = vec3(u_pyramidPos.x + halfSize, u_pyramidPos.y + halfSize, baseZ);
    vec3 p3 = vec3(u_pyramidPos.x - halfSize, u_pyramidPos.y + halfSize, baseZ);
    vec3 apex = vec3(u_pyramidPos.x, u_pyramidPos.y, baseZ + u_pyramidHeight);

    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = u_pyramidColor;

    float candidateT;
    vec3 candidateNormal;

    if (intersectTriangle(ro, rd, p0, p1, apex, candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectTriangle(ro, rd, p1, p2, apex, candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectTriangle(ro, rd, p2, p3, apex, candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }
    if (intersectTriangle(ro, rd, p3, p0, apex, candidateT, candidateNormal) && candidateT < tHit) {
        tHit = candidateT;
        normal = candidateNormal;
    }

    return tHit < INF;
}

// 写实计算机：底座 + 支颈 + 显示器外壳 + 自发光屏幕 + 键盘。坐落在桌面 u_tableTopHeight 上。
// 玩家从 +y 方向看，故屏幕朝 +y 面。材质 6.0 = 自发光屏幕。
bool intersectComputer(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.1);
    material = MAT_PLASTIC;
    if (u_computerPresent < 0.5) {
        return false;
    }

    float dz = u_tableTopHeight;
    float cx = u_computerPos.x;
    float cy = u_computerPos.y;
    vec3 dark = vec3(0.11, 0.12, 0.14);
    vec3 body = vec3(0.10, 0.11, 0.13);

    // 底座
    hitBox(ro, rd, vec3(cx - 0.11, cy - 0.09, dz), vec3(cx + 0.11, cy + 0.06, dz + 0.035), dark, MAT_PLASTIC, tHit, normal, albedo, material);
    // 支颈
    hitBox(ro, rd, vec3(cx - 0.03, cy - 0.03, dz + 0.035), vec3(cx + 0.03, cy + 0.02, dz + 0.17), dark, MAT_PLASTIC, tHit, normal, albedo, material);
    // 显示器外壳
    hitBox(ro, rd, vec3(cx - 0.21, cy - 0.05, dz + 0.16), vec3(cx + 0.21, cy + 0.045, dz + 0.50), body, MAT_PLASTIC, tHit, normal, albedo, material);
    // 屏幕（自发光，朝 +y，略凸出）
    hitBox(ro, rd, vec3(cx - 0.185, cy + 0.045, dz + 0.195), vec3(cx + 0.185, cy + 0.055, dz + 0.465), vec3(0.25, 1.0, 0.55), MAT_EMISSIVE, tHit, normal, albedo, material);
    // 键盘
    hitBox(ro, rd, vec3(cx - 0.17, cy + 0.10, dz), vec3(cx + 0.17, cy + 0.26, dz + 0.03), vec3(0.16, 0.16, 0.18), MAT_PLASTIC, tHit, normal, albedo, material);

    return tHit < INF;
}

// 写实椅子：座面 + 靠背（+y 侧）+ 四条腿。
bool intersectChair(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.32, 0.21, 0.16);
    material = MAT_VINYL;
    if (u_chairPresent < 0.5) {
        return false;
    }

    float cx = u_chairPos.x;
    float cy = u_chairPos.y;
    vec3 seatCol = vec3(0.32, 0.21, 0.16);
    vec3 frameCol = vec3(0.20, 0.14, 0.11);
    float seatTop = 0.46;

    // 座面
    hitBox(ro, rd, vec3(cx - 0.20, cy - 0.20, seatTop - 0.05), vec3(cx + 0.20, cy + 0.20, seatTop), seatCol, MAT_VINYL, tHit, normal, albedo, material);
    // 靠背
    hitBox(ro, rd, vec3(cx - 0.18, cy + 0.16, seatTop), vec3(cx + 0.18, cy + 0.20, seatTop + 0.42), seatCol, MAT_VINYL, tHit, normal, albedo, material);
    // 四条腿
    hitBox(ro, rd, vec3(cx - 0.185, cy - 0.185, 0.0), vec3(cx - 0.149, cy - 0.149, seatTop - 0.05), frameCol, MAT_WOOD, tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx + 0.149, cy - 0.185, 0.0), vec3(cx + 0.185, cy - 0.149, seatTop - 0.05), frameCol, MAT_WOOD, tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx - 0.185, cy + 0.149, 0.0), vec3(cx - 0.149, cy + 0.185, seatTop - 0.05), frameCol, MAT_WOOD, tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx + 0.149, cy + 0.149, 0.0), vec3(cx + 0.185, cy + 0.185, seatTop - 0.05), frameCol, MAT_WOOD, tHit, normal, albedo, material);

    return tHit < INF;
}

// 空调：挂在墙面的水平长方体（机体 + 底部出风口 + 随状态变色的指示灯）。
// u_acPos = (中心 x, 贴墙的 y 面)；机体自该墙面沿 +y 伸入房间。指示灯为材质6自发光。
bool intersectAC(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.9);
    material = MAT_PAPER;
    if (u_acPresent < 0.5) {
        return false;
    }

    float cx = u_acPos.x;
    float wy = u_acPos.y;        // 贴墙 y 面
    float top = u_acTopHeight;   // 顶部高度
    float bot = top - 0.34;      // 机体高约 0.34m
    float dep = 0.22;            // 伸入房间深度
    vec3 bodyCol = vec3(0.93, 0.93, 0.91);

    // 机体
    hitBox(ro, rd, vec3(cx - 0.55, wy, bot), vec3(cx + 0.55, wy + dep, top), bodyCol, MAT_PAPER, tHit, normal, albedo, material);
    // 底部出风口（深色）
    hitBox(ro, rd, vec3(cx - 0.52, wy + 0.02, bot - 0.04), vec3(cx + 0.52, wy + dep + 0.01, bot + 0.02), vec3(0.16, 0.17, 0.19), MAT_PLASTIC, tHit, normal, albedo, material);
    // 状态指示灯：关=暗 / 制冷=蓝 / 制热=橙
    vec3 ind = (u_acState > 1.5) ? vec3(1.0, 0.45, 0.15)
             : (u_acState > 0.5) ? vec3(0.20, 0.60, 1.00)
             : vec3(0.05, 0.05, 0.06);
    hitBox(ro, rd, vec3(cx + 0.40, wy + dep, top - 0.12), vec3(cx + 0.50, wy + dep + 0.012, top - 0.05), ind, MAT_EMISSIVE, tHit, normal, albedo, material);

    return tHit < INF;
}

// 遥控器：放在桌面的小盒子（机体 + 自发光屏幕）。被拿起时 u_remotePresent=0 不渲染。
bool intersectRemote(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.15);
    material = MAT_PLASTIC;
    if (u_remotePresent < 0.5) {
        return false;
    }

    float cx = u_remotePos.x;
    float cy = u_remotePos.y;
    float z0 = u_remoteTopHeight;
    // 机体（细长，深炭灰，便于在浅色床/沙发上区分）
    hitBox(ro, rd, vec3(cx - 0.035, cy - 0.10, z0), vec3(cx + 0.035, cy + 0.10, z0 + 0.022), vec3(0.10, 0.11, 0.14), MAT_PLASTIC, tHit, normal, albedo, material);
    // 屏幕（自发光青色，更醒目）
    hitBox(ro, rd, vec3(cx - 0.026, cy - 0.088, z0 + 0.022), vec3(cx + 0.026, cy - 0.02, z0 + 0.024), vec3(0.30, 0.95, 0.85), MAT_EMISSIVE, tHit, normal, albedo, material);
    return tHit < INF;
}

void hitClockHand(vec3 ro, vec3 rd, vec3 center, vec2 direction, float length, float width,
    vec3 handColor, inout float tHit, inout vec3 normal, inout vec3 albedo, inout float material)
{
    float c = direction.y;
    float s = direction.x;
    vec2 offset = ro.xz - center.xz;
    vec3 localRo = vec3(offset.x * c - offset.y * s, ro.y - center.y,
        offset.x * s + offset.y * c);
    vec3 localRd = vec3(rd.x * c - rd.z * s, rd.y, rd.x * s + rd.z * c);
    float candidateT;
    vec3 candidateNormal;
    if (intersectAABB(localRo, localRd, vec3(-width, 0.0, -0.025),
        vec3(width, 0.014, length), candidateT, candidateNormal)
        && candidateT > EPSILON && candidateT < tHit) {
        tHit = candidateT;
        normal = vec3(candidateNormal.x * c + candidateNormal.z * s,
            candidateNormal.y, -candidateNormal.x * s + candidateNormal.z * c);
        albedo = handColor;
        material = MAT_PLASTIC;
    }
}

bool intersectWallClock(vec3 ro, vec3 rd, out float tHit, out vec3 normal,
    out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 1.0, 0.0);
    albedo = vec3(0.0);
    material = MAT_WOOD;
    if (u_clockPresent < 0.5) return false;

    float cx = u_clockPos.x;
    float wy = u_clockPos.y;
    float cz = u_clockPos.z;
    hitBox(ro, rd, vec3(cx - 0.255, wy + 0.010, cz - 0.255),
        vec3(cx + 0.255, wy + 0.065, cz + 0.255), vec3(0.16, 0.10, 0.055), MAT_WOOD,
        tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx - 0.215, wy + 0.065, cz - 0.215),
        vec3(cx + 0.215, wy + 0.078, cz + 0.215), vec3(0.88, 0.84, 0.72), MAT_PAPER,
        tHit, normal, albedo, material);

    vec3 tick = vec3(0.20, 0.12, 0.055);
    hitBox(ro, rd, vec3(cx - 0.017, wy + 0.078, cz + 0.168),
        vec3(cx + 0.017, wy + 0.092, cz + 0.208), tick, MAT_WOOD,
        tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx - 0.017, wy + 0.078, cz - 0.208),
        vec3(cx + 0.017, wy + 0.092, cz - 0.168), tick, MAT_WOOD,
        tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx + 0.168, wy + 0.078, cz - 0.017),
        vec3(cx + 0.208, wy + 0.092, cz + 0.017), tick, MAT_WOOD,
        tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx - 0.208, wy + 0.078, cz - 0.017),
        vec3(cx - 0.168, wy + 0.092, cz + 0.017), tick, MAT_WOOD,
        tHit, normal, albedo, material);

    vec3 handCenter = vec3(cx, wy + 0.078, cz);
    hitClockHand(ro, rd, handCenter, u_clockHourHand, 0.115, 0.018, vec3(0.12),
        tHit, normal, albedo, material);
    hitClockHand(ro, rd, handCenter, u_clockMinuteHand, 0.170, 0.012, vec3(0.08),
        tHit, normal, albedo, material);
    hitBox(ro, rd, vec3(cx - 0.018, wy + 0.078, cz - 0.018),
        vec3(cx + 0.018, wy + 0.096, cz + 0.018), vec3(0.48, 0.30, 0.10), MAT_WOOD,
        tHit, normal, albedo, material);
    return tHit < INF;
}

vec2 calendarDepth(float wallY, float fromWall, float toWall)
{
    float y0 = wallY + u_calendarFacing * fromWall;
    float y1 = wallY + u_calendarFacing * toWall;
    return vec2(min(y0, y1), max(y0, y1));
}

bool intersectWallCalendar(vec3 ro, vec3 rd, out float tHit, out vec3 normal,
    out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 1.0, 0.0);
    albedo = vec3(0.0);
    material = MAT_PAPER;
    if (u_calendarPresent < 0.5) return false;
    float cx = u_calendarPos.x;
    float wy = u_calendarPos.y;
    float cz = u_calendarPos.z;
    vec2 bodyDepth = calendarDepth(wy, 0.012, 0.050);
    vec2 faceDepth = calendarDepth(wy, 0.050, 0.068);
    hitBox(ro, rd, vec3(cx - 0.30, bodyDepth.x, cz - 0.35),
        vec3(cx + 0.30, bodyDepth.y, cz + 0.35), vec3(0.82, 0.78, 0.66), MAT_PAPER,
        tHit, normal, albedo, material);
    float pageT;
    vec3 pageNormal;
    if (intersectAABB(ro, rd, vec3(cx - 0.285, faceDepth.x, cz - 0.335),
        vec3(cx + 0.285, faceDepth.y, cz + 0.335), pageT, pageNormal)
        && pageT > EPSILON && pageT < tHit) {
        vec3 hitPosition = ro + rd * pageT;
        vec2 uv = vec2((hitPosition.x - (cx - 0.285)) / 0.57,
            1.0 - (hitPosition.z - (cz - 0.335)) / 0.67);
        if (u_calendarFacing < 0.0) uv.x = 1.0 - uv.x;
        tHit = pageT;
        normal = pageNormal;
        albedo = Texel(u_calendarTex, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
        material = MAT_PAPER;
    }
    return tHit < INF;
}

vec4 getPlacedBook(int index)
{
    if (index == 0) return u_placedBook0;
    if (index == 1) return u_placedBook1;
    if (index == 2) return u_placedBook2;
    if (index == 3) return u_placedBook3;
    if (index == 4) return u_placedBook4;
    if (index == 5) return u_placedBook5;
    if (index == 6) return u_placedBook6;
    if (index == 7) return u_placedBook7;
    if (index == 8) return u_placedBook8;
    if (index == 9) return u_placedBook9;
    if (index == 10) return u_placedBook10;
    return u_placedBook11;
}

vec3 getBookColor(int index)
{
    if (index == 1) return u_bookColor1;
    if (index == 2) return u_bookColor2;
    if (index == 3) return u_bookColor3;
    if (index == 4) return u_bookColor4;
    if (index == 5) return u_bookColor5;
    return u_bookColor6;
}

bool intersectPlacedBook(vec3 ro, vec3 rd, vec4 data, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    material = MAT_PAPER;
    int ci = int(data.w + 0.5);
    albedo = getBookColor(ci);
    hitBox(ro, rd, data.xyz + vec3(-0.075, -0.11, 0.0),
        data.xyz + vec3(0.075, 0.11, 0.055), albedo, MAT_PAPER,
        tHit, normal, albedo, material);
    return tHit < INF;
}

vec2 rot2(vec2 v, float c, float s)
{
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 在家具局部坐标系中拼出写实复合体（多个 AABB）。原点为家具中心，开口朝局部 +y。
void buildFurniture(int ftype, vec3 ro, vec3 rd, float bookMask, float bookStyles, inout float t, inout vec3 n, inout vec3 a, inout float m)
{
    if (ftype == 1) {
        // 床：床架 + 床垫 + 床头板(+y) + 枕头
        hitBox(ro, rd, vec3(-0.75, -1.0, 0.05), vec3(0.75, 1.0, 0.30), vec3(0.32, 0.22, 0.14), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.72, -0.95, 0.30), vec3(0.72, 0.85, 0.50), vec3(0.84, 0.82, 0.78), MAT_FABRIC, t, n, a, m);
        hitBox(ro, rd, vec3(-0.75, 0.92, 0.30), vec3(0.75, 1.05, 0.85), vec3(0.30, 0.20, 0.13), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.55, 0.50, 0.50), vec3(0.55, 0.84, 0.63), vec3(0.93, 0.91, 0.87), MAT_FABRIC, t, n, a, m);
    } else if (ftype == 2) {
        // 沙发：底座 + 坐垫 + 靠背(-y) + 左右扶手
        hitBox(ro, rd, vec3(-0.90, -0.42, 0.10), vec3(0.90, 0.30, 0.40), vec3(0.30, 0.35, 0.40), MAT_FABRIC, t, n, a, m);
        hitBox(ro, rd, vec3(-0.78, -0.40, 0.40), vec3(0.78, 0.26, 0.52), vec3(0.34, 0.40, 0.46), MAT_FABRIC, t, n, a, m);
        hitBox(ro, rd, vec3(-0.90, -0.42, 0.40), vec3(0.90, -0.26, 0.82), vec3(0.30, 0.35, 0.40), MAT_FABRIC, t, n, a, m);
        hitBox(ro, rd, vec3(-0.90, -0.42, 0.10), vec3(-0.76, 0.30, 0.56), vec3(0.27, 0.32, 0.37), MAT_FABRIC, t, n, a, m);
        hitBox(ro, rd, vec3(0.76, -0.42, 0.10), vec3(0.90, 0.30, 0.56), vec3(0.27, 0.32, 0.37), MAT_FABRIC, t, n, a, m);
    } else if (ftype == 3) {
        // 书架：每一位二进制掩码对应一本可独立拾取的书。
        hitBox(ro, rd, vec3(-0.45, -0.14, 0.0), vec3(0.45, -0.10, 2.0), vec3(0.28, 0.19, 0.12), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.45, -0.14, 0.0), vec3(-0.41, 0.14, 2.0), vec3(0.36, 0.25, 0.16), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(0.41, -0.14, 0.0), vec3(0.45, 0.14, 2.0), vec3(0.36, 0.25, 0.16), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.45, -0.14, 1.96), vec3(0.45, 0.14, 2.0), vec3(0.36, 0.25, 0.16), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.45, -0.14, 0.0), vec3(0.45, 0.14, 0.04), vec3(0.30, 0.21, 0.13), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.41, -0.10, 0.66), vec3(0.41, 0.14, 0.70), vec3(0.34, 0.24, 0.15), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.41, -0.10, 1.30), vec3(0.41, 0.14, 1.34), vec3(0.34, 0.24, 0.15), MAT_WOOD, t, n, a, m);
        for (int bi = 0; bi < 6; bi++) {
            float bitValue = mod(floor(bookMask / exp2(float(bi))), 2.0);
            if (bitValue > 0.5) {
                int row = bi / 2;
                int col = bi - row * 2;
                float bx = -0.30 + float(col) * 0.28 + float(row) * 0.05;
                float bz = (row == 0) ? 0.04 : ((row == 1) ? 0.70 : 1.34);
                int styleIndex = int(mod(floor(bookStyles / pow(8.0, float(bi))), 8.0) + 0.5);
                vec3 bookColor = getBookColor(styleIndex);
                hitBox(ro, rd, vec3(bx - 0.075, -0.06, bz), vec3(bx + 0.075, 0.12, bz + 0.54), bookColor, MAT_PAPER, t, n, a, m);
            }
        }
    } else if (ftype == 4) {
        // 柜子：柜体 + 顶板
        hitBox(ro, rd, vec3(-0.45, -0.22, 0.0), vec3(0.45, 0.22, 0.85), vec3(0.45, 0.34, 0.22), MAT_WOOD, t, n, a, m);
        hitBox(ro, rd, vec3(-0.47, -0.24, 0.85), vec3(0.47, 0.24, 0.90), vec3(0.33, 0.24, 0.15), MAT_WOOD, t, n, a, m);
    } else if (ftype == 6) {
        // 吊灯：从天花板垂下的电线 + 灯罩 + 自发光灯泡（材质 6）
        float ceil = u_ceilingHeight;
        hitBox(ro, rd, vec3(-0.02, -0.02, ceil - 0.45), vec3(0.02, 0.02, ceil), vec3(0.05, 0.05, 0.05), MAT_PLASTIC, t, n, a, m);
        hitBox(ro, rd, vec3(-0.20, -0.20, ceil - 0.70), vec3(0.20, 0.20, ceil - 0.45), vec3(0.20, 0.17, 0.13), MAT_VINYL, t, n, a, m);
        hitBox(ro, rd, vec3(-0.08, -0.08, ceil - 0.80), vec3(0.08, 0.08, ceil - 0.66), vec3(1.0, 0.88, 0.6), MAT_EMISSIVE, t, n, a, m);
    }
}

// 单个家具实例求交：把光线变换到家具局部系做轴对齐求交，再把法线转回世界系。
bool intersectFurniture(vec3 ro, vec3 rd, vec4 fdata, out float tHit, out vec3 normal, out vec3 albedo, out float material)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.3);
    material = MAT_WOOD;

    int ftype = int(fdata.z + 0.5);
    if (ftype <= 0) {
        return false;
    }

    vec3 center = vec3(fdata.x, fdata.y, 0.0);
    float yaw = fdata.w;
    float ci = cos(-yaw);
    float si = sin(-yaw);
    vec3 lro = ro - center;
    lro.xy = rot2(lro.xy, ci, si);
    vec3 lrd = rd;
    lrd.xy = rot2(lrd.xy, ci, si);

    float lt = INF;
    vec3 ln = vec3(0.0, 0.0, 1.0);
    vec3 la = vec3(0.3);
    float lm = 2.0;
    float bookMask = (fdata.x < 5.0) ? u_bookshelfMaskLeft : u_bookshelfMaskRight;
    float bookStyles = (fdata.x < 5.0) ? u_bookshelfBookStylesLeft : u_bookshelfBookStylesRight;
    buildFurniture(ftype, lro, lrd, bookMask, bookStyles, lt, ln, la, lm);

    if (lt < INF) {
        float cf = cos(yaw);
        float sf = sin(yaw);
        tHit = lt;
        normal = vec3(rot2(ln.xy, cf, sf), ln.z);
        albedo = la;
        material = lm;
        return true;
    }
    return false;
}

vec4 getFurniture(int index)
{
    if (index == 0) return u_furniture0;
    if (index == 1) return u_furniture1;
    if (index == 2) return u_furniture2;
    if (index == 3) return u_furniture3;
    if (index == 4) return u_furniture4;
    if (index == 5) return u_furniture5;
    if (index == 6) return u_furniture6;
    return u_furniture7;
}

bool occludesMaze(vec3 ro, vec3 rd, float maxDist)
{
    if (abs(rd.x) < EPSILON && abs(rd.y) < EPSILON) {
        return false;
    }

    vec2 mapPos = floor(ro.xy / u_tileSize);
    vec2 rayStep = sign(rd.xy);
    vec2 deltaDist = vec2(
        (abs(rd.x) < EPSILON) ? INF : abs(u_tileSize / rd.x),
        (abs(rd.y) < EPSILON) ? INF : abs(u_tileSize / rd.y)
    );

    if (abs(rayStep.x) < EPSILON) {
        rayStep.x = 1.0;
    }
    if (abs(rayStep.y) < EPSILON) {
        rayStep.y = 1.0;
    }

    vec2 sideDist;
    sideDist.x = (rd.x < 0.0)
        ? (ro.x - mapPos.x * u_tileSize) / max(abs(rd.x), EPSILON)
        : ((mapPos.x + 1.0) * u_tileSize - ro.x) / max(abs(rd.x), EPSILON);
    sideDist.y = (rd.y < 0.0)
        ? (ro.y - mapPos.y * u_tileSize) / max(abs(rd.y), EPSILON)
        : ((mapPos.y + 1.0) * u_tileSize - ro.y) / max(abs(rd.y), EPSILON);

    for (int i = 0; i < MAX_DDA_STEPS; i++) {
        float candidateT;

        if (sideDist.x < sideDist.y) {
            candidateT = sideDist.x;
            sideDist.x += deltaDist.x;
            mapPos.x += rayStep.x;
        } else {
            candidateT = sideDist.y;
            sideDist.y += deltaDist.y;
            mapPos.y += rayStep.y;
        }

        if (candidateT > maxDist) {
            break;
        }

        float wallHeight;
        if (sampleWallShadow(mapPos, wallHeight)) {
            float hitZ = ro.z + rd.z * candidateT;
            if (hitZ >= 0.0 && hitZ <= wallHeight) {
                return true;
            }
        }
    }

    return false;
}

bool isOccluded(vec3 ro, vec3 rd, float maxDist)
{
    if (occludesMaze(ro, rd, maxDist)) {
        return true;
    }

    float tHit;
    vec3 normal;
    vec3 albedo;

    if (intersectTable(ro, rd, tHit, normal, albedo) && tHit > EPSILON && tHit < maxDist) {
        return true;
    }
    if (intersectPyramid(ro, rd, tHit, normal, albedo) && tHit > EPSILON && tHit < maxDist) {
        return true;
    }

    // 计算机 / 椅子 / 家具：用各自的真实几何参与遮挡，使阴影与物体外形一致
    // （之前用整体包围盒，导致显示器投出方块状阴影）
    float to;
    vec3 no;
    vec3 ao;
    float mo;
    if (u_computerPresent > 0.5 && intersectComputer(ro, rd, to, no, ao, mo) && to > EPSILON && to < maxDist) {
        return true;
    }
    if (u_chairPresent > 0.5 && intersectChair(ro, rd, to, no, ao, mo) && to > EPSILON && to < maxDist) {
        return true;
    }
    for (int fi = 0; fi < 8; fi++) {
        if (fi >= u_furnitureCount) {
            break;
        }
        if (intersectFurniture(ro, rd, getFurniture(fi), to, no, ao, mo) && to > EPSILON && to < maxDist) {
            return true;
        }
    }

    return false;
}

vec3 getPointLightPos(int index)
{
    if (index == 0) return u_pointLightPos0;
    if (index == 1) return u_pointLightPos1;
    if (index == 2) return u_pointLightPos2;
    if (index == 3) return u_pointLightPos3;
    if (index == 4) return u_pointLightPos4;
    return u_pointLightPos5;
}

vec3 getPointLightColor(int index)
{
    if (index == 0) return u_pointLightColor0;
    if (index == 1) return u_pointLightColor1;
    if (index == 2) return u_pointLightColor2;
    if (index == 3) return u_pointLightColor3;
    if (index == 4) return u_pointLightColor4;
    return u_pointLightColor5;
}

vec2 getPointLightParams(int index)
{
    if (index == 0) return u_pointLightParams0;
    if (index == 1) return u_pointLightParams1;
    if (index == 2) return u_pointLightParams2;
    if (index == 3) return u_pointLightParams3;
    if (index == 4) return u_pointLightParams4;
    return u_pointLightParams5;
}

bool intersectMaze(vec3 ro, vec3 rd, out float tHit, out vec3 normal, out vec3 albedo)
{
    tHit = INF;
    normal = vec3(0.0, 0.0, 1.0);
    albedo = vec3(0.0);

    vec2 mapPos = floor(ro.xy / u_tileSize);
    vec2 rayStep = sign(rd.xy);
    vec2 deltaDist = vec2(
        (abs(rd.x) < EPSILON) ? INF : abs(u_tileSize / rd.x),
        (abs(rd.y) < EPSILON) ? INF : abs(u_tileSize / rd.y)
    );

    if (abs(rayStep.x) < EPSILON) {
        rayStep.x = 1.0;
    }
    if (abs(rayStep.y) < EPSILON) {
        rayStep.y = 1.0;
    }

    vec2 sideDist;
    sideDist.x = (rd.x < 0.0)
        ? (ro.x - mapPos.x * u_tileSize) / max(abs(rd.x), EPSILON)
        : ((mapPos.x + 1.0) * u_tileSize - ro.x) / max(abs(rd.x), EPSILON);
    sideDist.y = (rd.y < 0.0)
        ? (ro.y - mapPos.y * u_tileSize) / max(abs(rd.y), EPSILON)
        : ((mapPos.y + 1.0) * u_tileSize - ro.y) / max(abs(rd.y), EPSILON);

    for (int i = 0; i < MAX_DDA_STEPS; i++) {
        float side;
        float candidateT;

        if (sideDist.x < sideDist.y) {
            candidateT = sideDist.x;
            sideDist.x += deltaDist.x;
            mapPos.x += rayStep.x;
            side = 0.0;
        } else {
            candidateT = sideDist.y;
            sideDist.y += deltaDist.y;
            mapPos.y += rayStep.y;
            side = 1.0;
        }

        if (candidateT > FAR_CLIP) {
            break;
        }

        vec3 candidateAlbedo;
        float wallHeight;
        if (sampleWall(mapPos, candidateAlbedo, wallHeight)) {
            float hitZ = ro.z + rd.z * candidateT;
            if (hitZ >= 0.0 && hitZ <= wallHeight) {
                tHit = candidateT;
                albedo = candidateAlbedo;
                normal = (side < 0.5)
                    ? vec3(-rayStep.x, 0.0, 0.0)
                    : vec3(0.0, -rayStep.y, 0.0);
                return true;
            }
        }
    }

    return false;
}

vec3 shadeSurface(vec3 pos, vec3 rd, vec3 normal, vec3 albedo, float materialId, float dist)
{
    // 自发光屏幕/灯泡（材质 6）：不受光照/阴影影响，直接发亮
    if (materialId > 5.5 && materialId < 6.5) {
        float fogE = exp(-dist * 0.055);
        return mix(vec3(0.63, 0.62, 0.60), albedo, fogE);
    }

    // 室内封闭场景：屋子已有天花板（材质 5 的天花板平面），完全封闭。
    // 因此不计算太阳等室外平行光，仅由环境光打底 + 室内点光源照明。
    float ambient = 0.20;
    vec3 viewDir = normalize(-rd);
    vec3 shadowOrigin = pos + normal * 0.015;
    albedo = materialDetail(pos, normal, albedo, materialId);

    if (materialId > 3.5 && materialId < 4.5) {
        float checker = mod(floor(pos.x) + floor(pos.y), 2.0);
        albedo *= mix(0.90, 1.06, checker);
        float grout = step(0.94, fract(pos.x)) + step(0.94, fract(pos.y));
        albedo *= mix(1.0, 0.78, saturate(grout));
    }

    if (materialId > 4.5) {
        ambient = 0.12;
    }

    vec3 lit = albedo * ambient;

    for (int i = 0; i < MAX_POINT_LIGHTS; i++) {
        if (i >= u_pointLightCount) {
            break;
        }

        vec3 pointLightPos = getPointLightPos(i);
        vec3 pointLightColor = getPointLightColor(i);
        vec2 pointLightParams = getPointLightParams(i);
        float intensity = pointLightParams.x;
        float radius = pointLightParams.y;

        vec3 toLight = pointLightPos - pos;
        float pointDist = max(length(toLight), EPSILON);
        if (pointDist < radius && intensity > 0.0) {
            vec3 pointDir = toLight / pointDist;
            float pointMask = max(dot(normal, pointDir), 0.0);
            float wrappedMask = saturate((dot(normal, pointDir) + 0.32) / 1.32) * 0.34;
            float pointFalloff = 1.0 - pointDist / radius;
            float pointVisibility = isOccluded(shadowOrigin, pointDir, pointDist - 0.02) ? 0.0 : 1.0;
            float softVisibility = mix(0.18, 1.0, pointVisibility);
            float pointDiffuse = (pointMask + wrappedMask) * pointFalloff * pointFalloff
                * intensity * softVisibility;

            vec3 pointHalfVector = normalize(pointDir + viewDir);
            float pointSpecular = pow(max(dot(normal, pointHalfVector), 0.0), 28.0) * pointFalloff * intensity * pointVisibility;

            lit += albedo * pointLightColor * pointDiffuse;
            lit += pointLightColor * pointSpecular * 0.18;
        }
    }

    // float fog = exp(-dist * 0.008);
    // vec3 fogColor = vec3(0.63, 0.62, 0.60);
    // return mix(fogColor, lit, fog);
    return lit;
}

vec3 renderScene(vec2 screen_coords)
{
    vec2 uv = ((screen_coords + u_jitter) / u_renderSize) * 2.0 - 1.0;
    vec3 ro = vec3(u_playerPos, u_playerHeight);
    vec3 rd = normalize(
        u_cameraForward
        + u_cameraRight * uv.x * u_tanHalfFov
        - u_cameraUp * uv.y * (u_tanHalfFov * u_invAspect)
    );

    float bestT = INF;
    vec3 bestNormal = vec3(0.0, 0.0, 1.0);
    vec3 bestAlbedo = vec3(0.0);
    float bestMaterial = 0.0;

    float tMaze;
    vec3 mazeNormal;
    vec3 mazeAlbedo;
    if (intersectMaze(ro, rd, tMaze, mazeNormal, mazeAlbedo)) {
        updateNearestHit(tMaze, mazeNormal, mazeAlbedo, MAT_WALL, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tTable;
    vec3 tableNormal;
    vec3 tableAlbedo;
    if (intersectTable(ro, rd, tTable, tableNormal, tableAlbedo)) {
        updateNearestHit(tTable, tableNormal, tableAlbedo, MAT_WOOD, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tPyramid;
    vec3 pyramidNormal;
    vec3 pyramidAlbedo;
    if (intersectPyramid(ro, rd, tPyramid, pyramidNormal, pyramidAlbedo)) {
        updateNearestHit(tPyramid, pyramidNormal, pyramidAlbedo, MAT_PLASTIC, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tComp;
    vec3 compNormal;
    vec3 compAlbedo;
    float compMaterial;
    if (intersectComputer(ro, rd, tComp, compNormal, compAlbedo, compMaterial)) {
        updateNearestHit(tComp, compNormal, compAlbedo, compMaterial, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tChair;
    vec3 chairNormal;
    vec3 chairAlbedo;
    float chairMaterial;
    if (intersectChair(ro, rd, tChair, chairNormal, chairAlbedo, chairMaterial)) {
        updateNearestHit(tChair, chairNormal, chairAlbedo, chairMaterial, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tAc;
    vec3 acNormal;
    vec3 acAlbedo;
    float acMaterial;
    if (intersectAC(ro, rd, tAc, acNormal, acAlbedo, acMaterial)) {
        updateNearestHit(tAc, acNormal, acAlbedo, acMaterial, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tRemote;
    vec3 remoteNormal;
    vec3 remoteAlbedo;
    float remoteMaterial;
    if (intersectRemote(ro, rd, tRemote, remoteNormal, remoteAlbedo, remoteMaterial)) {
        updateNearestHit(tRemote, remoteNormal, remoteAlbedo, remoteMaterial, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tClock;
    vec3 clockNormal;
    vec3 clockAlbedo;
    float clockMaterial;
    if (intersectWallClock(ro, rd, tClock, clockNormal, clockAlbedo, clockMaterial)) {
        updateNearestHit(tClock, clockNormal, clockAlbedo, clockMaterial,
            bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tCalendar;
    vec3 calendarNormal;
    vec3 calendarAlbedo;
    float calendarMaterial;
    if (intersectWallCalendar(ro, rd, tCalendar, calendarNormal, calendarAlbedo, calendarMaterial)) {
        updateNearestHit(tCalendar, calendarNormal, calendarAlbedo, calendarMaterial,
            bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    for (int bi = 0; bi < 12; bi++) {
        if (bi >= u_placedBookCount) break;
        float tb;
        vec3 nb;
        vec3 ab;
        float mb;
        if (intersectPlacedBook(ro, rd, getPlacedBook(bi), tb, nb, ab, mb)) {
            updateNearestHit(tb, nb, ab, mb, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }
    if (u_bookPreview.w >= 0.0) {
        float tp;
        vec3 np;
        vec3 ap;
        float mp;
        if (intersectPlacedBook(ro, rd, u_bookPreview, tp, np, ap, mp)) {
            updateNearestHit(tp, np, ap, mp, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }

    for (int fi = 0; fi < 8; fi++) {
        if (fi >= u_furnitureCount) {
            break;
        }
        float tf;
        vec3 nf;
        vec3 af;
        float mf;
        if (intersectFurniture(ro, rd, getFurniture(fi), tf, nf, af, mf)) {
            updateNearestHit(tf, nf, af, mf, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }

    if (rd.z < -EPSILON) {
        float tFloor = (0.0 - ro.z) / rd.z;
        if (tFloor > EPSILON) {
            updateNearestHit(tFloor, vec3(0.0, 0.0, 1.0), vec3(0.47, 0.43, 0.36), MAT_FLOOR, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }

    if (rd.z > EPSILON) {
        float tCeiling = (u_ceilingHeight - ro.z) / rd.z;
        if (tCeiling > EPSILON) {
            updateNearestHit(tCeiling, vec3(0.0, 0.0, -1.0), vec3(0.18, 0.20, 0.23), MAT_CEILING, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }

    if (bestT >= FAR_CLIP) {
        return skyColor(rd);
    }

    vec3 hitPos = ro + rd * bestT;
    return shadeSurface(hitPos, rd, bestNormal, bestAlbedo, bestMaterial, bestT);
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    // 每像素只做一次完整场景求交。静止画面由 TAAU 的跨帧 jitter 累积亚像素信息，
    // 相机运动时由后续 FXAA 处理边缘，避免旧路径额外执行四次完整光投。
    return vec4(renderScene(screen_coords), 1.0) * color;
}
