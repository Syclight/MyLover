const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");

const root = path.resolve(__dirname, "..");
const sourceRoots = ["engine", "games", "samples", "tests"];
const errors = [];

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

function rel(file) {
  return path.relative(root, file).replace(/\\/g, "/");
}

function checkNoRemovedNamespace() {
  const files = [
    ...sourceRoots.flatMap((dir) => walk(path.join(root, dir))),
    path.join(root, "main.lua"),
    path.join(root, "project.lua"),
    path.join(root, "conf.lua"),
  ].filter((file) => file.endsWith(".lua"));
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    if (/require\s*\(\s*["']src\./.test(text)) {
      errors.push(`${rel(file)} imports removed src namespace`);
    }
  }
}

function checkManifestPaths() {
  const manifests = [
    ...walk(path.join(root, "engine")),
    ...walk(path.join(root, "games")),
    ...walk(path.join(root, "samples")),
  ].filter((file) => /manifest.*\.lua$/.test(path.basename(file)) || rel(file).includes("/assets/manifest/"));

  const pathPattern = /path\s*=\s*["']([^"']+)["']/g;
  for (const manifest of manifests) {
    const text = fs.readFileSync(manifest, "utf8");
    let match;
    while ((match = pathPattern.exec(text))) {
      const assetPath = match[1];
      if (!fs.existsSync(path.join(root, assetPath))) {
        errors.push(`${rel(manifest)} references missing asset ${assetPath}`);
      }
    }
  }
}

function checkMaps() {
  const result = childProcess.spawnSync(process.execPath, ["tools/build_maps.js", "--check"], {
    cwd: root,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    errors.push(`map check failed:\n${result.stdout || ""}${result.stderr || ""}`.trim());
  }
}

checkNoRemovedNamespace();
checkManifestPaths();
checkMaps();

if (errors.length > 0) {
  console.error(errors.map((error) => `ERROR ${error}`).join("\n"));
  process.exit(1);
}

console.log("project validation passed");
