#!/usr/bin/env node
"use strict";
// REAL Luau syntax gate. The historical Lua 5.1 parser and Lua 5.3/Fengari
// transforms erase type annotations, so they cannot detect Studio parse errors.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const root = path.resolve(__dirname, "..");
const bin = path.join(root, ".tools", "bin", "luau-compile");
if (!fs.existsSync(bin)) {
  console.error("Missing official Luau compiler. Run: bash tools/install-luau.sh");
  process.exit(2);
}
const files = [];
function walk(dir) {
  for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, item.name);
    if (item.isDirectory()) walk(file);
    else if (file.endsWith(".luau")) files.push(file);
  }
}
walk(path.join(root, "code"));
files.sort();
const result = spawnSync(bin, ["--null", ...files], { cwd: root, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
if (result.error || result.status !== 0 || result.stderr) {
  console.error(result.error || result.stderr || result.stdout || "Luau compiler failed");
  process.exit(1);
}
console.log(`Official Luau compiler: ${files.length} game scripts compiled`);
