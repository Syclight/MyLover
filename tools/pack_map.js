const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function usage() {
  console.error('Usage: node tools/pack_map.js <input.json> <output.smap> [chunkSize]');
  process.exit(1);
}

const inputPath = process.argv[2];
const outputPath = process.argv[3];
const chunkSize = Number(process.argv[4] || 32);

if (!inputPath || !outputPath || !Number.isFinite(chunkSize) || chunkSize <= 0) {
  usage();
}

const raw = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const metadata = raw.metadata || {};
const tileLayer = (raw.layers || []).find(layer => layer.type === 'tilelayer');
const objectLayer = (raw.layers || []).find(layer => layer.type === 'objectlayer');

if (!tileLayer || !Array.isArray(tileLayer.data)) {
  throw new Error('Tile layer not found');
}

const width = Number(metadata.width || 0);
const height = Number(metadata.height || 0);
if (width <= 0 || height <= 0) {
  throw new Error('Invalid map dimensions');
}

const chunkColumns = Math.ceil(width / chunkSize);
const chunkRows = Math.ceil(height / chunkSize);
const chunkBuffers = [];
const chunks = [];
let offset = 0;

for (let cy = 0; cy < chunkRows; cy++) {
  for (let cx = 0; cx < chunkColumns; cx++) {
    const chunkWidth = Math.min(chunkSize, width - cx * chunkSize);
    const chunkHeight = Math.min(chunkSize, height - cy * chunkSize);
    const rawTiles = Buffer.alloc(chunkWidth * chunkHeight * 2);
    let writeOffset = 0;

    for (let y = 0; y < chunkHeight; y++) {
      for (let x = 0; x < chunkWidth; x++) {
        const mapX = cx * chunkSize + x;
        const mapY = cy * chunkSize + y;
        const tileId = Number(tileLayer.data[mapY * width + mapX] || 0);
        rawTiles.writeUInt16LE(tileId, writeOffset);
        writeOffset += 2;
      }
    }

    const compressed = zlib.deflateSync(rawTiles, { level: 9 });
    chunkBuffers.push(compressed);
    chunks.push({
      cx,
      cy,
      width: chunkWidth,
      height: chunkHeight,
      offset,
      size: compressed.length
    });
    offset += compressed.length;
  }
}

const header = {
  version: 1,
  metadata,
  chunkSize,
  chunkColumns,
  chunkRows,
  tilesets: raw.tilesets || [],
  objects: objectLayer?.objects || [],
  chunks
};

const magic = Buffer.from('SMAPBIN1', 'ascii');
const headerBuffer = Buffer.from(JSON.stringify(header), 'utf8');
const headerLength = Buffer.alloc(4);
headerLength.writeUInt32LE(headerBuffer.length, 0);

const output = Buffer.concat([magic, headerLength, headerBuffer, ...chunkBuffers]);
fs.writeFileSync(outputPath, output);
console.log(`Packed ${path.basename(inputPath)} -> ${path.basename(outputPath)} (${output.length} bytes)`);
