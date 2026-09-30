"use strict";

const fs = require("fs");
const path = require("path");

/**
 * Return the source tree used by the current repository.
 *
 * TIDEKEEPER is intentionally Explorer-first and stores its Studio tree under
 * `tidekeeper/code/`. This resolver is rooted at `tidekeeper/`, so the copied
 * tools point at the right tree with no arguments. The `src/` fallback is kept
 * only so a bare checkout does not crash; there is no Rojo project here.
 */
function defaultSourceRoot(repoRoot = path.resolve(__dirname, "../..")) {
	const code = path.join(repoRoot, "code");
	if (fs.existsSync(code) && fs.statSync(code).isDirectory()) {
		return code;
	}
	return path.join(repoRoot, "src");
}

module.exports = { defaultSourceRoot };
