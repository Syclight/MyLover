// 程序化生成长筱场景的水面/树叶贴图（CC0 源站不可达时的离线替代）。
//   node games/nagashino/tools/gen_textures.js
// 输出（512x512，全部无缝平铺）：
//   assets/images/water_normal.png  水面法线：整数波矢量的多八度方向波（解析导数）
//   assets/images/leaves_color.png  叶簇 albedo：多层椭圆叶片散布 + 顶光/底阴
//   assets/images/leaves_normal.png 叶簇法线：由叶片穹顶高度场差分而来
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 512;
const OUT_DIR = path.join(__dirname, '..', 'assets', 'images');

// ---------- 最小 PNG 编码器（RGBA8，filter 0） ----------
const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function writePNG(filePath, width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0; // filter none
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  fs.writeFileSync(filePath, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]));
  console.log(`gen_textures: wrote ${path.relative(process.cwd(), filePath)}`);
}

// 可复现的伪随机（不依赖 Math.random 的进程差异）
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------- 水面法线：整数波矢量 → 完美平铺 ----------
function generateWaterNormal() {
  const rand = mulberry32(20250712);
  const waves = [];
  const addBand = (count, kMin, kMax, ampScale) => {
    for (let i = 0; i < count; i++) {
      const mag = kMin + rand() * (kMax - kMin);
      const ang = rand() * Math.PI * 2;
      // 波矢量取整数格点：sin(2π(kx·x+ky·y)/SIZE) 在图幅边界处天然连续
      const kx = Math.round(Math.cos(ang) * mag);
      const ky = Math.round(Math.sin(ang) * mag);
      if (kx === 0 && ky === 0) continue;
      const k = Math.sqrt(kx * kx + ky * ky);
      waves.push({
        kx, ky,
        amp: ampScale / Math.pow(k, 1.15), // 大波振幅大，符合波谱
        phase: rand() * Math.PI * 2,
      });
    }
  };
  addBand(6, 2, 4, 5.2);    // 涌浪
  addBand(10, 5, 11, 4.0);  // 中波
  addBand(14, 12, 26, 2.6); // 细纹
  addBand(10, 27, 48, 1.4); // 微波光斑

  const strength = 2.6; // 法线整体强度（shader 侧还有 normalScale 可调）
  const rgba = Buffer.alloc(SIZE * SIZE * 4);
  const twoPi = Math.PI * 2;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      let dhdx = 0, dhdy = 0;
      for (const w of waves) {
        const arg = twoPi * (w.kx * x + w.ky * y) / SIZE + w.phase;
        const c = Math.cos(arg) * w.amp * twoPi / SIZE;
        dhdx += c * w.kx;
        dhdy += c * w.ky;
      }
      let nx = -dhdx * strength, ny = -dhdy * strength, nz = 1;
      const inv = 1 / Math.sqrt(nx * nx + ny * ny + nz * nz);
      nx *= inv; ny *= inv; nz *= inv;
      const o = (y * SIZE + x) * 4;
      rgba[o] = Math.round((nx * 0.5 + 0.5) * 255);
      rgba[o + 1] = Math.round((ny * 0.5 + 0.5) * 255);
      rgba[o + 2] = Math.round((nz * 0.5 + 0.5) * 255);
      rgba[o + 3] = 255;
    }
  }
  writePNG(path.join(OUT_DIR, 'water_normal.png'), SIZE, SIZE, rgba);
}

// ---------- 叶簇：albedo + 高度场法线 ----------
function generateLeaves() {
  const rand = mulberry32(19700528);
  const albedo = Buffer.alloc(SIZE * SIZE * 4);
  const heights = new Float32Array(SIZE * SIZE);

  // 底色：暗绿 + 低频平铺噪声（整数波），模拟树冠深处阴影
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const n = 0.5
        + 0.28 * Math.sin((2 * Math.PI * (3 * x + 2 * y)) / SIZE + 1.7)
        + 0.22 * Math.sin((2 * Math.PI * (5 * x - 4 * y)) / SIZE + 4.1);
      const o = (y * SIZE + x) * 4;
      albedo[o] = Math.round(24 + 18 * n);
      albedo[o + 1] = Math.round(56 + 30 * n);
      albedo[o + 2] = Math.round(20 + 13 * n);
      albedo[o + 3] = 255;
    }
  }

  // 叶片：分三层由暗到亮散布（底层大而暗=深处，顶层小而亮=受光）
  const layers = [
    { count: 420, sizeMin: 11, sizeMax: 20, tone: 0.52, lift: 0.35 },
    { count: 520, sizeMin: 8, sizeMax: 15, tone: 0.80, lift: 0.7 },
    { count: 460, sizeMin: 5, sizeMax: 11, tone: 1.12, lift: 1.0 },
  ];
  for (const layer of layers) {
    for (let i = 0; i < layer.count; i++) {
      const cx = rand() * SIZE, cy = rand() * SIZE;
      const len = layer.sizeMin + rand() * (layer.sizeMax - layer.sizeMin);
      const wid = len * (0.45 + rand() * 0.25);
      const rot = rand() * Math.PI * 2;
      const cosR = Math.cos(rot), sinR = Math.sin(rot);
      // 每片叶子的绿色调抖动
      const hueJitter = rand();
      const baseR = (48 + hueJitter * 40) * layer.tone;
      const baseG = (118 + hueJitter * 58) * layer.tone;
      const baseB = (34 + hueJitter * 24) * layer.tone;
      const reach = Math.ceil(len) + 1;
      for (let dy = -reach; dy <= reach; dy++) {
        for (let dx = -reach; dx <= reach; dx++) {
          // 旋转到叶片局部系，椭圆判定
          const lx = dx * cosR + dy * sinR;
          const ly = -dx * sinR + dy * cosR;
          const d = (lx * lx) / (len * len * 0.25) + (ly * ly) / (wid * wid * 0.25);
          if (d > 1) continue;
          const px = ((Math.round(cx + dx) % SIZE) + SIZE) % SIZE; // 环绕→平铺
          const py = ((Math.round(cy + dy) % SIZE) + SIZE) % SIZE;
          const dome = Math.sqrt(1 - d); // 叶片穹顶高度
          const idx = py * SIZE + px;
          // 顶部受光、根部沉入阴影：沿叶长方向的亮度梯度
          const light = 0.62 + 0.55 * (lx / len + 0.5) * dome;
          const o = idx * 4;
          albedo[o] = Math.min(255, Math.round(baseR * light));
          albedo[o + 1] = Math.min(255, Math.round(baseG * light));
          albedo[o + 2] = Math.min(255, Math.round(baseB * light));
          const h = dome * layer.lift;
          if (h > heights[idx]) heights[idx] = h;
        }
      }
    }
  }
  writePNG(path.join(OUT_DIR, 'leaves_color.png'), SIZE, SIZE, albedo);

  // 高度场 → 法线（环绕差分，保持平铺）
  const normal = Buffer.alloc(SIZE * SIZE * 4);
  const nStrength = 2.2;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const xp = (x + 1) % SIZE, xm = (x + SIZE - 1) % SIZE;
      const yp = (y + 1) % SIZE, ym = (y + SIZE - 1) % SIZE;
      const dhdx = (heights[y * SIZE + xp] - heights[y * SIZE + xm]) * 0.5;
      const dhdy = (heights[yp * SIZE + x] - heights[ym * SIZE + x]) * 0.5;
      let nx = -dhdx * nStrength, ny = -dhdy * nStrength, nz = 1;
      const inv = 1 / Math.sqrt(nx * nx + ny * ny + nz * nz);
      nx *= inv; ny *= inv; nz *= inv;
      const o = (y * SIZE + x) * 4;
      normal[o] = Math.round((nx * 0.5 + 0.5) * 255);
      normal[o + 1] = Math.round((ny * 0.5 + 0.5) * 255);
      normal[o + 2] = Math.round((nz * 0.5 + 0.5) * 255);
      normal[o + 3] = 255;
    }
  }
  writePNG(path.join(OUT_DIR, 'leaves_normal.png'), SIZE, SIZE, normal);
}

generateWaterNormal();
generateLeaves();
