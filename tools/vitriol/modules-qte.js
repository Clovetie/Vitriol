"use strict";

/**
 * Module map for the QTE package (qte/).
 *
 * The package is deliberately separate from the Vitriol place: it is a product
 * you drop into ReplicatedStorage > QTE and nothing else has to come with it.
 * This map is what lets the repository's harness still exercise every line of it,
 * with the same Luau->Lua transform as the Vitriol suite:
 *
 *   node tools/vitriol-smoke-test.js \
 *        --modules tools/vitriol/modules-qte.js \
 *        --tests   tools/vitriol/tests-qte.luau
 *
 * Logical names must stay unique (requires resolve by last path segment).
 */

module.exports = {
	label: "QTE package (qte/)",
	modules: {
		QTEConfig: "qte/Config/QTEConfig.luau",
		RNG: "qte/Lib/RNG.luau",
		Signal: "qte/Lib/Signal.luau",
		QTECatalog: "qte/Lib/QTECatalog.luau",
		QTEEngine: "qte/Lib/QTEEngine.luau",
		QTEDirector: "qte/Lib/QTEDirector.luau",
	},
};
