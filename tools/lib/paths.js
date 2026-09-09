"use strict";

const fs = require("fs");
const path = require("path");

/**
 * Return the source tree used by the current repository.
 *
 * Vitriol is intentionally Explorer-first and stores its Studio tree under
 * `code/`. Older BRINE tools were written for `src/`; retaining the fallback
 * lets those tools remain useful to a future checkout of the original layout
 * without making a new Rojo project part of this repository.
 */
function defaultSourceRoot(repoRoot = path.resolve(__dirname, "../..")) {
	const code = path.join(repoRoot, "code");
	if (fs.existsSync(code) && fs.statSync(code).isDirectory()) {
		return code;
	}
	return path.join(repoRoot, "src");
}

module.exports = { defaultSourceRoot };
