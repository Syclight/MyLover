// OBJ → SMSHBIN1 离线转换（运行时零解析，见 engine/rendering/MeshBin.lua）。
// 解析语义与 engine/rendering/ObjLoader.lua 完全一致：
//   顶点格式 pos3 + uv2 + norm3（8 float32 LE / 顶点），UV 的 v 轴翻转，
//   扇形三角化，负数相对索引，无 vn 时按面法线补齐，索引流 0 基。
// 二进制布局与 MeshBin.encode 一致；头部 JSON 只需语义一致（解码经 json.decode，与键序无关）。
const fs = require('fs');

function usage() {
  console.error('Usage: node tools/obj2mesh.js <input.obj> <output.mesh>');
  process.exit(1);
}

const inputPath = process.argv[2];
const outputPath = process.argv[3];
if (!inputPath || !outputPath) {
  usage();
}

const text = fs.readFileSync(inputPath, 'utf8');

const positions = [];
const uvs = [];
const normals = [];
const vertices = []; // 每项 [x,y,z,u,v,nx,ny,nz]
const indices = [];  // 1 基（写出时转 0 基，与 MeshBin.encode 相同）
const dedupe = new Map();
let radiusSq = 0;

// o/g 对象分段（Blender 每个 Object 一段）；indexStart 1 基，喂 Mesh:setDrawRange
const objects = [];
let current = null;
let currentMaterial = null;

function finishObject() {
  if (!current) return;
  current.indexCount = indices.length - current.indexStart + 1;
  if (current.indexCount > 0) {
    const cx = (current.min[0] + current.max[0]) / 2;
    const cy = (current.min[1] + current.max[1]) / 2;
    const cz = (current.min[2] + current.max[2]) / 2;
    objects.push({
      name: current.name,
      material: current.material,
      indexStart: current.indexStart,
      indexCount: current.indexCount,
      center: [cx, cy, cz],
      boundingRadius: Math.hypot(current.max[0] - cx, current.max[1] - cy, current.max[2] - cz),
    });
  }
  current = null;
}

function beginObject(name) {
  finishObject();
  current = {
    name,
    material: currentMaterial,
    indexStart: indices.length + 1,
    min: [Infinity, Infinity, Infinity],
    max: [-Infinity, -Infinity, -Infinity],
  };
}

function setMaterial(name) {
  currentMaterial = name;
  if (current && indices.length >= current.indexStart) beginObject(current.name);
  else if (current) current.material = name;
}

function resolveIndex(index, count) {
  return index < 0 ? count + index + 1 : index;
}

function addVertex(vi, ti, ni, faceNormal) {
  const key = ni ? `${vi}/${ti || 0}/${ni}` : `${vi}/${ti || 0}/f${indices.length}`;
  const existing = dedupe.get(key);
  if (existing) return existing;

  const p = positions[vi - 1];
  if (!p) throw new Error(`face references missing vertex ${vi}`);
  const t = ti ? uvs[ti - 1] : null;
  const n = ni ? normals[ni - 1] : faceNormal;

  vertices.push([p[0], p[1], p[2], t ? t[0] : 0, t ? 1 - t[1] : 0, n[0], n[1], n[2]]);
  dedupe.set(key, vertices.length);
  return vertices.length;
}

for (const line of text.split(/\r?\n/)) {
  const tokens = line.trim().split(/\s+/);
  const head = tokens.shift();
  if (head === 'v') {
    const [x, y, z] = tokens.map(Number);
    positions.push([x, y, z]);
    radiusSq = Math.max(radiusSq, x * x + y * y + z * z);
  } else if (head === 'vt') {
    uvs.push([Number(tokens[0]), Number(tokens[1])]);
  } else if (head === 'vn') {
    normals.push(tokens.map(Number));
  } else if (head === 'o' || head === 'g') {
    beginObject(tokens.join(' '));
  } else if (head === 'usemtl') {
    setMaterial(tokens.join(' '));
  } else if (head === 'f') {
    if (!current) beginObject('default');
    const corners = tokens.map(token => {
      const [vi, ti, ni] = token.split('/');
      return [
        resolveIndex(Number(vi), positions.length),
        ti ? resolveIndex(Number(ti), uvs.length) : 0,
        ni ? resolveIndex(Number(ni), normals.length) : 0,
      ];
    });
    if (corners.length < 3) continue;

    for (const corner of corners) {
      const p = positions[corner[0] - 1];
      if (p) {
        for (let axis = 0; axis < 3; axis++) {
          current.min[axis] = Math.min(current.min[axis], p[axis]);
          current.max[axis] = Math.max(current.max[axis], p[axis]);
        }
      }
    }

    let faceNormal = null;
    if (!corners[0][2]) {
      const a = positions[corners[0][0] - 1];
      const b = positions[corners[1][0] - 1];
      const c = positions[corners[2][0] - 1];
      const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      const v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      let n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
      const len = Math.hypot(n[0], n[1], n[2]);
      if (len > 1e-12) n = n.map(value => value / len);
      faceNormal = n;
    }

    const first = addVertex(corners[0][0], corners[0][1], corners[0][2], faceNormal);
    let prev = addVertex(corners[1][0], corners[1][1], corners[1][2], faceNormal);
    for (let i = 2; i < corners.length; i++) {
      const current = addVertex(corners[i][0], corners[i][1], corners[i][2], faceNormal);
      indices.push(first, prev, current);
      prev = current;
    }
  }
}

finishObject();

const indexType = vertices.length <= 65535 ? 'uint16' : 'uint32';
// 与 engine/utils/json 的 encode 输出保持一致的紧凑 JSON（无空格）
const header = Buffer.from(JSON.stringify({
  format: 'pos3_uv2_norm3',
  vertexCount: vertices.length,
  indexCount: indices.length,
  indexType,
  boundingRadius: Math.sqrt(radiusSq),
  objects,
}), 'utf8');

const headerLength = Buffer.alloc(4);
headerLength.writeUInt32LE(header.length, 0);

const vertexBuffer = Buffer.alloc(vertices.length * 8 * 4);
vertices.forEach((vertex, i) => {
  vertex.forEach((value, j) => vertexBuffer.writeFloatLE(value, (i * 8 + j) * 4));
});

const indexStride = indexType === 'uint16' ? 2 : 4;
const indexBuffer = Buffer.alloc(indices.length * indexStride);
indices.forEach((index, i) => {
  if (indexType === 'uint16') indexBuffer.writeUInt16LE(index - 1, i * 2);
  else indexBuffer.writeUInt32LE(index - 1, i * 4);
});

fs.writeFileSync(outputPath, Buffer.concat([
  Buffer.from('SMSHBIN1', 'ascii'), headerLength, header, vertexBuffer, indexBuffer,
]));

console.log(`obj2mesh: ${vertices.length} vertices, ${indices.length} indices (${indexType}) -> ${outputPath}`);
