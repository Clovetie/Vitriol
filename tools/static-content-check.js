#!/usr/bin/env node
"use strict";
// Fail closed if a Vitriol source reintroduces runtime Instance construction.
// The editor-only job under jobs/ is intentionally not part of code/.
const fs = require("fs");
const path = require("path");
const root = path.join(__dirname, "..", "code");
const offenders = [];
let count = 0;
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(file);
    else if (file.endsWith(".luau")) {
      count++;
      const src = fs.readFileSync(file, "utf8");
      // Comments can mention these APIs; test calls/constructors only, with
      // allowance for whitespace between identifier and open paren.
      if (/\bInstance\s*\.\s*new\s*\(|:\s*Clone\s*\(/.test(src)) {
        offenders.push(path.relative(root, file));
      }
    }
  }
}
walk(root);
const author = fs.readFileSync(path.join(__dirname, "..", "jobs", "author_static_vitriol.lua"), "utf8");
if (!author.includes('assert(not RunService:IsRunning()')) offenders.push("editor job has no Edit-mode guard");
if (offenders.length) {
  console.error("Runtime Instance constructor/clone or unsafe editor job:", offenders.join(", "));
  process.exit(1);
}
console.log(`Authored-content gate: ${count} Luau scripts contain no Instance.new()/Clone() calls; editor job requires Edit mode`);
