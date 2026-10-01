--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/GameConfig (ModuleScript)
--
-- Global caps and budgets. Every key here is read by name somewhere in the
-- tree; `find-dead-config.js` enforces that. Do not add a knob before the
-- reader exists.
--
-- Layer: Config (data only -- no requires, no services, no functions).

return {
	-- Schema / save-format ---------------------------------------------------
	SCHEMA_VERSION = 3,
	OLDEST_SUPPORTED_VERSION = 1,

	-- Resolve-on-read (doc 04 section 3) -------------------------------------
	-- 27 tide epochs is 27 * 22357 s = 6.99 days. Anything older is not
	-- simulated; it collapses into a single LONG_ABSENCE summary.
	MAX_CATCHUP_EPOCHS = 27,
	-- Chunking hint consumed by the iteration-3 scheduler and asserted by the
	-- iteration-2 harness so the two never drift apart.
	EPOCHS_PER_RESOLVE_TICK = 4,

	-- Arrivals ---------------------------------------------------------------
	MAX_ARRIVALS_PER_EPOCH = 8,
	MAX_RESIDENT_DRIFTERS = 24,
	MAX_BERTHS = 3,

	-- Post shape -------------------------------------------------------------
	MAX_SHELF_SLOTS = 24,
	MAX_STORE_ENTRIES = 160,
	MAX_STOCK_PER_ENTRY = 65535,
	MAX_COIN = 4294967295,
	MAX_TIER = 4,
	MAX_COMB_NODES = 12,
	VISITOR_RING_SIZE = 48,

	-- Ledger -----------------------------------------------------------------
	MAX_LEDGER_RESIDENT = 200,
	MAX_LEDGER_SLOTS = 6,

	-- Wire budgets (doc 05) --------------------------------------------------
	MAX_POST_BLOB_BYTES = 6144,
	MAX_ORDERS_BYTES = 1024,
	DRIFTER_BLOB_BYTES = 68,
	RECEIPT_BLOB_BYTES = 28,

	-- Identity ---------------------------------------------------------------
	-- Drifter ids are `owner * DRIFTER_ID_EPOCH_SPAN + (epoch % DRIFTER_ID_EPOCH_SPAN)`.
	-- owner must stay below OWNER_ID_MAX so the product is exactly
	-- representable in an IEEE-754 double (2^53). See doc 05 section 4 and the
	-- iteration-2 correction note in HANDOFF.md.
	DRIFTER_ID_EPOCH_SPAN = 8192,
	OWNER_ID_MAX = 1099511627776, -- 2^40
}
