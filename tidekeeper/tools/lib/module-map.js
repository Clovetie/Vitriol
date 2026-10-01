/**
 * module-map.js — the pure modules, in one place.
 *
 * `luau-native.js` resolves a `require` by the LAST PATH SEGMENT, so these
 * keys are the names the game's own `require(Tidekeeper.Domain.Visit)` calls
 * resolve to. That also means module base names must stay globally unique
 * across the tree; two files called `Util.luau` would silently collide.
 *
 * This list used to be copy-pasted into `tidekeeper-luau-bench.js` and
 * `tidekeeper-session-test.js`. A third consumer (`tidekeeper-luau-test.js`)
 * made that untenable: a module added to one list and not the others gives a
 * `nil` require inside the VM, which surfaces as a confusing runtime error in
 * one tool while the others stay green.
 *
 * PURE contains only the modules with no DataModel dependency whatsoever --
 * everything under Config, Lib, Shared and Domain. CLIENT adds the presenter
 * layer, which is also pure (D25) but is not needed to benchmark the
 * simulation.
 */

const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const CODE = path.join(ROOT, "code", "ReplicatedStorage", "Tidekeeper");

const PURE = {
	// Config
	GameConfig: `${CODE}/Config/GameConfig.luau`,
	TideConfig: `${CODE}/Config/TideConfig.luau`,
	EconomyConfig: `${CODE}/Config/EconomyConfig.luau`,
	DrifterConfig: `${CODE}/Config/DrifterConfig.luau`,
	OrdersConfig: `${CODE}/Config/OrdersConfig.luau`,
	FindsConfig: `${CODE}/Config/FindsConfig.luau`,
	LettersConfig: `${CODE}/Config/LettersConfig.luau`,
	SeedsConfig: `${CODE}/Config/SeedsConfig.luau`,
	BadgesConfig: `${CODE}/Config/BadgesConfig.luau`,
	NotifyConfig: `${CODE}/Config/NotifyConfig.luau`,
	// Lib
	MathExt: `${CODE}/Lib/MathExt.luau`,
	Hash: `${CODE}/Lib/Hash.luau`,
	RNG: `${CODE}/Lib/RNG.luau`,
	Tables: `${CODE}/Lib/Tables.luau`,
	Signal: `${CODE}/Lib/Signal.luau`,
	Codec: `${CODE}/Lib/Codec.luau`,
	Schema: `${CODE}/Lib/Schema.luau`,
	Tide: `${CODE}/Lib/Tide.luau`,
	// Shared
	Version: `${CODE}/Shared/Version.luau`,
	DrifterCodec: `${CODE}/Shared/DrifterCodec.luau`,
	PostCodec: `${CODE}/Shared/PostCodec.luau`,
	ReceiptCodec: `${CODE}/Shared/ReceiptCodec.luau`,
	NetContract: `${CODE}/Shared/NetContract.luau`,
	// Domain
	Standing: `${CODE}/Domain/Standing.luau`,
	Almanac: `${CODE}/Domain/Almanac.luau`,
	Drifter: `${CODE}/Domain/Drifter.luau`,
	Post: `${CODE}/Domain/Post.luau`,
	Orders: `${CODE}/Domain/Orders.luau`,
	Badges: `${CODE}/Domain/Badges.luau`,
	Ledger: `${CODE}/Domain/Ledger.luau`,
	Visit: `${CODE}/Domain/Visit.luau`,
	Resolve: `${CODE}/Domain/Resolve.luau`,
};

const CLIENT = {
	Strings: `${CODE}/Client/Strings.luau`,
	Format: `${CODE}/Client/Format.luau`,
	LedgerView: `${CODE}/Client/LedgerView.luau`,
	TideView: `${CODE}/Client/TideView.luau`,
	PostView: `${CODE}/Client/PostView.luau`,
	OrdersView: `${CODE}/Client/OrdersView.luau`,
	ChartView: `${CODE}/Client/ChartView.luau`,
	AlmanacView: `${CODE}/Client/AlmanacView.luau`,
	LetterView: `${CODE}/Client/LetterView.luau`,
	DispatchView: `${CODE}/Client/DispatchView.luau`,
	ClientBootstrap: `${CODE}/Client/ClientBootstrap.luau`,
};

// Server layers. These DO depend on injected platform objects, so they are
// only loadable by the session harness (which supplies a fake DataModel) --
// never by the pure runners.
const SERVER_CODE = path.join(ROOT, "code", "ServerStorage", "Tidekeeper");
const SCRIPTS_CODE = path.join(ROOT, "code", "ServerScriptService", "Tidekeeper");

const SERVER = {
	// Shared/Remotes is the single sanctioned remote factory (doc 01 section
	// 4). It lives under ReplicatedStorage with the pure modules but it calls
	// GetService, so it is deliberately NOT in PURE -- the pure runners must
	// stay loadable with no DataModel at all.
	Remotes: `${CODE}/Shared/Remotes.luau`,
	// L1 Adapters
	DataStoreAdapter: `${SERVER_CODE}/Adapters/DataStoreAdapter.luau`,
	MemoryAdapter: `${SERVER_CODE}/Adapters/MemoryAdapter.luau`,
	NotifyAdapter: `${SERVER_CODE}/Adapters/NotifyAdapter.luau`,
	PolicyAdapter: `${SERVER_CODE}/Adapters/PolicyAdapter.luau`,
	// L3 Services
	CadenceService: `${SERVER_CODE}/Services/CadenceService.luau`,
	ExchangeService: `${SERVER_CODE}/Services/ExchangeService.luau`,
	LedgerService: `${SERVER_CODE}/Services/LedgerService.luau`,
	NotifyService: `${SERVER_CODE}/Services/NotifyService.luau`,
	ShowcaseService: `${SERVER_CODE}/Services/ShowcaseService.luau`,
	PostService: `${SERVER_CODE}/Services/PostService.luau`,
	PlayerService: `${SERVER_CODE}/Services/PlayerService.luau`,
	Bootstrap: `${SERVER_CODE}/Services/Bootstrap.luau`,
	// L4 Remote handlers + diagnostics (loaded so that a syntax or layering
	// error in them fails this suite rather than waiting for Studio)
	SessionHandler: `${SCRIPTS_CODE}/RemoteHandlers/SessionHandler.luau`,
	HistoryHandler: `${SCRIPTS_CODE}/RemoteHandlers/HistoryHandler.luau`,
	PostHandler: `${SCRIPTS_CODE}/RemoteHandlers/PostHandler.luau`,
	DispatchHandler: `${SCRIPTS_CODE}/RemoteHandlers/DispatchHandler.luau`,
	DebugHandler: `${SCRIPTS_CODE}/RemoteHandlers/DebugHandler.luau`,
	Profiler: `${SCRIPTS_CODE}/Diagnostics/Profiler.luau`,
	BudgetMeter: `${SCRIPTS_CODE}/Diagnostics/BudgetMeter.luau`,
};

const MODULES = { ...PURE, ...CLIENT };

/**
 * TWO PATH CONVENTIONS, AND THEY ARE NOT INTERCHANGEABLE.
 *
 * `luau-native.js` reads files itself and wants ABSOLUTE paths. The fengari
 * harness resolves through `luau-transform.read()`, which joins against the
 * tidekeeper root, so it wants paths RELATIVE to that root. Handing the wrong
 * kind to either produces a doubled-up path like
 * `tidekeeper/home/user/.../GameConfig.luau`, which is confusing precisely
 * because it looks like a missing file rather than a joined one.
 *
 * Rather than leave that as folklore, the map is exported both ways and the
 * caller picks by name.
 */
function toRelative(map) {
	const out = {};
	for (const [name, abs] of Object.entries(map)) {
		out[name] = path.relative(ROOT, abs).split(path.sep).join("/");
	}
	return out;
}

module.exports = {
	CODE,
	ROOT,
	// absolute -- for luau-native.js (it opens the file itself)
	PURE,
	CLIENT,
	MODULES,
	// relative to tidekeeper/ -- for the fengari harness
	SERVER,
	PURE_REL: toRelative(PURE),
	CLIENT_REL: toRelative(CLIENT),
	MODULES_REL: toRelative(MODULES),
	// Everything the session harness loads: pure + client + server, plus the
	// fake platform, which is required like any other module.
	SESSION_REL: {
		...toRelative({ ...PURE, ...CLIENT, ...SERVER }),
		FakePlatform: "tools/tests/fake-platform.lua",
		SessionPrelude: "tools/tests/session-prelude.lua",
	},
};
