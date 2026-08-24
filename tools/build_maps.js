const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const checkOnly = process.argv.includes('--check');
const maps = [
  ['games/surveillance/assets/maps/apartment_1.json', 'games/surveillance/assets/maps/apartment_1.smap'],
  ['samples/shader_maze/assets/maps/shader_maze_1.json', 'samples/shader_maze/assets/maps/shader_maze_1.smap'],
];

let failed = false;
for (const [input, output] of maps) {
  const inputPath = path.join(root, input);
  const outputPath = path.join(root, output);
  const target = checkOnly
    ? path.join(os.tmpdir(), `love-map-${process.pid}-${path.basename(output)}`)
    : outputPath;

  const result = spawnSync(process.execPath, [path.join(__dirname, 'pack_map.js'), inputPath, target], {
    stdio: checkOnly ? 'pipe' : 'inherit',
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr || `Failed to build ${input}\n`);
    failed = true;
    continue;
  }

  if (checkOnly) {
    const current = fs.existsSync(outputPath) ? fs.readFileSync(outputPath) : null;
    const generated = fs.readFileSync(target);
    fs.unlinkSync(target);
    if (!current || !current.equals(generated)) {
      console.error(`STALE ${output} (source: ${input})`);
      failed = true;
    } else {
      console.log(`OK    ${output}`);
    }
  }
}

if (failed) process.exit(1);
