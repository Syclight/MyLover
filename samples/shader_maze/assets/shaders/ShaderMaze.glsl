extern Image u_mapTex;
extern vec2 u_mapSize;
extern vec2 u_mapOrigin;
extern vec2 u_worldMapSize;
extern float u_tileSize;
extern vec2 u_renderSize;
extern vec2 u_jitter;
extern float u_subpixelAA;
extern vec2 u_playerPos;
extern float u_playerDir;
extern float u_playerPitch;
extern float u_fov;
extern float u_playerHeight;
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

float saturate(float x)
{
    return clamp(x, 0.0, 1.0);
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
    vec3 sunDir = normalize(vec3(-0.55, -0.35, 0.75));
    float ambient = 0.20;
    vec3 viewDir = normalize(-rd);
    vec3 shadowOrigin = pos + normal * 0.015;
    float sunVisibility = isOccluded(shadowOrigin, sunDir, FAR_CLIP) ? 0.0 : 1.0;
    float diffuse = max(dot(normal, sunDir), 0.0) * sunVisibility;
    vec3 halfVector = normalize(sunDir + viewDir);
    float specular = pow(max(dot(normal, halfVector), 0.0), 40.0) * sunVisibility;

    if (materialId > 3.5 && materialId < 4.5) {
        float checker = mod(floor(pos.x) + floor(pos.y), 2.0);
        albedo *= mix(0.90, 1.06, checker);
        float grout = step(0.94, fract(pos.x)) + step(0.94, fract(pos.y));
        albedo *= mix(1.0, 0.78, saturate(grout));
        diffuse *= 0.75;
    }

    if (materialId > 4.5) {
        diffuse *= 0.45;
        ambient = 0.12;
    }

    vec3 lit = albedo * (ambient + diffuse * 0.88);
    lit += specular * mix(0.02, 0.20, step(2.5, materialId));

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
        vec3 pointDir = toLight / pointDist;
        float pointMask = max(dot(normal, pointDir), 0.0);
        float pointFalloff = saturate(1.0 - pointDist / max(radius, EPSILON));
        float pointVisibility = isOccluded(shadowOrigin, pointDir, pointDist - 0.02) ? 0.0 : 1.0;
        float pointDiffuse = pointMask * pointFalloff * pointFalloff * intensity * pointVisibility;

        vec3 pointHalfVector = normalize(pointDir + viewDir);
        float pointSpecular = pow(max(dot(normal, pointHalfVector), 0.0), 28.0) * pointFalloff * intensity * pointVisibility;

        lit += albedo * pointLightColor * pointDiffuse;
        lit += pointLightColor * pointSpecular * 0.18;
    }

    float fog = exp(-dist * 0.055);
    vec3 fogColor = vec3(0.63, 0.62, 0.60);
    return mix(fogColor, lit, fog);
}

vec3 renderScene(vec2 screen_coords)
{
    vec2 uv = ((screen_coords + u_jitter) / u_renderSize) * 2.0 - 1.0;
    float aspect = u_renderSize.x / max(u_renderSize.y, 1.0);
    float tanHalfFov = tan(u_fov * 0.5);

    float cosPitch = cos(u_playerPitch);
    vec3 forward = normalize(vec3(cos(u_playerDir) * cosPitch, sin(u_playerDir) * cosPitch, sin(u_playerPitch)));
    vec3 right = normalize(vec3(-sin(u_playerDir), cos(u_playerDir), 0.0));
    vec3 up = normalize(cross(forward, right));

    vec3 ro = vec3(u_playerPos, u_playerHeight);
    vec3 rd = normalize(
        forward
        + right * uv.x * tanHalfFov
        - up * uv.y * (tanHalfFov / aspect)
    );

    float bestT = INF;
    vec3 bestNormal = vec3(0.0, 0.0, 1.0);
    vec3 bestAlbedo = vec3(0.0);
    float bestMaterial = 0.0;

    float tMaze;
    vec3 mazeNormal;
    vec3 mazeAlbedo;
    if (intersectMaze(ro, rd, tMaze, mazeNormal, mazeAlbedo)) {
        updateNearestHit(tMaze, mazeNormal, mazeAlbedo, 1.0, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tTable;
    vec3 tableNormal;
    vec3 tableAlbedo;
    if (intersectTable(ro, rd, tTable, tableNormal, tableAlbedo)) {
        updateNearestHit(tTable, tableNormal, tableAlbedo, 2.0, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    float tPyramid;
    vec3 pyramidNormal;
    vec3 pyramidAlbedo;
    if (intersectPyramid(ro, rd, tPyramid, pyramidNormal, pyramidAlbedo)) {
        updateNearestHit(tPyramid, pyramidNormal, pyramidAlbedo, 3.0, bestT, bestNormal, bestAlbedo, bestMaterial);
    }

    if (rd.z < -EPSILON) {
        float tFloor = (0.0 - ro.z) / rd.z;
        if (tFloor > EPSILON) {
            updateNearestHit(tFloor, vec3(0.0, 0.0, 1.0), vec3(0.47, 0.43, 0.36), 4.0, bestT, bestNormal, bestAlbedo, bestMaterial);
        }
    }

    if (rd.z > EPSILON) {
        float tCeiling = (u_ceilingHeight - ro.z) / rd.z;
        if (tCeiling > EPSILON) {
            updateNearestHit(tCeiling, vec3(0.0, 0.0, -1.0), vec3(0.18, 0.20, 0.23), 5.0, bestT, bestNormal, bestAlbedo, bestMaterial);
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
    vec3 finalColor = renderScene(screen_coords);

    if (u_subpixelAA > 0.5) {
        vec2 sampleRadius = vec2(0.35, 0.35);
        vec3 accum = vec3(0.0);

        accum += renderScene(screen_coords + vec2(-sampleRadius.x, -sampleRadius.y));
        accum += renderScene(screen_coords + vec2(sampleRadius.x, -sampleRadius.y));
        accum += renderScene(screen_coords + vec2(-sampleRadius.x, sampleRadius.y));
        accum += renderScene(screen_coords + vec2(sampleRadius.x, sampleRadius.y));

        finalColor = (finalColor + accum) / 5.0;
    }

    return vec4(finalColor, 1.0) * color;
}


