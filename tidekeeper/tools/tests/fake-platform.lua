-- tools/tests/fake-platform.lua
--
-- A fake Roblox DataModel, good enough to run TIDEKEEPER's REAL adapters and
-- services outside Roblox.
--
-- WHY THIS EXISTS RATHER THAN MOCK ADAPTERS
-- -----------------------------------------
-- The usual approach is to write a `FakeDataStoreAdapter` and inject that.
-- It tests nothing. The adapter is where every interesting bug in this game
-- lives: the retry classification, the budget deferral, the UpdateAsync
-- transform that removes and returns in one transaction, the lock protocol,
-- the "nil means new player but a failed read does not" distinction. Faking
-- the adapter means faking exactly the code that needs testing.
--
-- So the fake is BELOW the adapter: it is `DataStoreService`, and the real
-- `DataStoreAdapter` runs against it unmodified. Every request the game
-- makes is counted here, which is how the claim "five platform requests per
-- session" is measured rather than asserted.
--
-- WHAT IT MODELS, AND WHY EACH PIECE IS IN
--
--   * Request counts per type, so the session test can print a real number.
--   * Per-server, per-minute BUDGETS -- Read/Write/Remove 60 + 40 * players,
--     List 5 + 2 * players (re-verified 2026-10-01). The adapter defers when
--     the budget runs low, and that code path only ever executes here.
--   * Deterministic failure injection using the error strings Roblox
--     actually produces -- DataUpdateConflict, TotalRequestsOverLimit,
--     TotalMemoryOverLimit, RequestThrottled -- because the adapter
--     classifies by matching those strings, and a fake that invents its own
--     messages would let a classification bug through.
--   * A virtual clock. `task.wait` advances it instead of sleeping, so a
--     30-day, 200-session lifetime test runs in under a second and the
--     adapter's real backoff schedule (0, 0.5, 1.5, 4, 9 seconds) is
--     exercised exactly as written.
--   * MemoryStore hash maps and a queue, with TTL expiry driven off the same
--     clock.
--
-- WHAT IT DELIBERATELY DOES NOT MODEL
--   * Actual concurrency. Two "servers" are two adapter instances sharing
--     one fake backend, and interleaving is explicit in the test. Real
--     threads would make the test nondeterministic, which is the one thing
--     it may not be.
--   * Network latency as a distribution. Latency here is zero; the thing
--     under test is request COUNT and ordering, not wall time.

local FakePlatform = {}

-- --------------------------------------------------------------- utility

local function lcg(state)
	-- Numerical Recipes LCG, in doubles. Deterministic across runs and
	-- across machines, which matters more than statistical quality: a
	-- failure-injection schedule that changes between runs turns a red
	-- build into a coin flip.
	return { s = state % 4294967296 }
end

local function nextRandom(r)
	r.s = (r.s * 1664525 + 1013904223) % 4294967296
	return r.s / 4294967296
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in pairs(v) do
		out[k] = deepCopy(val)
	end
	return out
end

-- Roblox serialises DataStore values, so a caller cannot keep a live
-- reference to what it stored. Copying on the way in AND out reproduces
-- that, and it is the difference between a test that catches accidental
-- aliasing and one that does not.
local function store(v)
	return deepCopy(v)
end

-- ------------------------------------------------------- stub instances

-- `require(Tidekeeper.Domain.Post)` is rewritten to `TidekeeperRequire("Post")`
-- by the transform, so the instance tree never needs real modules in it. It
-- does need to EXIST, because every module opens with
-- `ReplicatedStorage:WaitForChild("Tidekeeper")`.
local Stub = {}
Stub.__index = function(self, key)
	local made = setmetatable({ _name = key, _children = {} }, getmetatable(self))
	rawset(self, key, made)
	return made
end

local function stubInstance(name)
	local self = setmetatable({ _children = {} }, Stub)
	rawset(self, "_name", name)
	rawset(self, "Name", name)
	rawset(self, "WaitForChild", function(s, child)
		return s[child]
	end)
	rawset(self, "FindFirstChild", function(s, child)
		return rawget(s, child)
	end)
	return self
end

FakePlatform.stubInstance = stubInstance

-- ------------------------------------------------------------ DataStore

local FakeDataStore = {}
FakeDataStore.__index = FakeDataStore

local function newDataStore(env, name)
	return setmetatable({ env = env, name = name, data = {}, keys = {} }, FakeDataStore)
end

-- Every entry point funnels through here: one place that counts, one place
-- that injects failure, one place that spends budget.
function FakeDataStore:charge(kind)
	local env = self.env
	local stats = env.stats.dataStore
	stats[kind] = (stats[kind] or 0) + 1
	stats.total = stats.total + 1
	env:spendBudget(kind)

	local inject = env.inject
	local roll = nextRandom(env.rng) * 1000
	if roll < (inject.conflictPerMille or 0) then
		stats.injectedConflicts = stats.injectedConflicts + 1
		error("DataUpdateConflict: the key was modified by another request", 0)
	end
	roll = nextRandom(env.rng) * 1000
	if roll < (inject.throttlePerMille or 0) then
		stats.injectedThrottles = stats.injectedThrottles + 1
		error("TotalRequestsOverLimit: RequestThrottled, try again later", 0)
	end
	roll = nextRandom(env.rng) * 1000
	if roll < (inject.quotaPerMille or 0) then
		stats.injectedQuota = stats.injectedQuota + 1
		error("TotalMemoryOverLimit: the experience is over its storage quota", 0)
	end
end

function FakeDataStore:GetAsync(key)
	self:charge("get")
	return store(self.data[key])
end

function FakeDataStore:SetAsync(key, value)
	self:charge("set")
	-- Real Roblox refuses this: "Argument 2 is missing or nil". Only
	-- RemoveAsync deletes an entry. The fake used to accept it and quietly
	-- behave like a remove, so code that lost a value on the way to a save
	-- would have looked like a successful delete here and thrown in
	-- production.
	if value == nil then
		error("SetAsync: Argument 2 is missing or nil", 0)
	end
	self.data[key] = store(value)
	self.keys[key] = true
	return true
end

-- The important one. Reads, applies the transform, writes, and returns the
-- NEW value -- which is what makes read-and-remove atomic, which is what
-- makes at-most-once Drifter delivery possible.
function FakeDataStore:UpdateAsync(key, transform)
	self:charge("update")

	-- ROBLOX MAY CALL THE TRANSFORM MORE THAN ONCE WITHIN ONE UpdateAsync.
	--
	-- From the API reference: "In cases where another game server updated the
	-- key in the short timespan between retrieving the key's current value
	-- and setting the key's value, UpdateAsync will call the function again,
	-- discarding the result of the previous call. The function will be called
	-- as many times as needed until the data is saved."
	--
	-- Until iteration 12 this fake called it EXACTLY ONCE, which made it more
	-- forgiving than the real thing in the most dangerous possible way: a
	-- transform that accumulates into an upvalue is correct here and wrong in
	-- production. Two adapters were doing exactly that (see
	-- `drainReceipts` and `allocLedgerPage`), and the suite could not see it.
	--
	-- `transformRetries` is a deterministic count, not a random one: the
	-- whole harness is seeded and reproducible (doc 04 section 5), and a
	-- flaky re-run would be worse than none. The discarded first result is
	-- genuinely discarded, exactly as Roblox describes.
	local retries = self.env.inject.transformRetries or 1
	local old = store(self.data[key])
	local new
	for _ = 1, retries do
		-- The value the key held when the losing attempt read it. Passing the
		-- same `old` is the realistic case for our access patterns (one
		-- writer per key, retrying against itself); what matters for
		-- correctness is that the transform RUNS AGAIN and its earlier
		-- return value is thrown away.
		new = transform(store(self.data[key]))
	end
	new = transform(old)
	if new == nil then
		return nil
	end
	if type(new) == "string" and #new > 4194304 then
		error("ItemValueSizeTooLarge: value exceeds 4 MB", 0)
	end
	self.data[key] = store(new)
	self.keys[key] = true
	return store(new)
end

function FakeDataStore:RemoveAsync(key)
	self:charge("remove")
	local old = self.data[key]
	self.data[key] = nil
	self.keys[key] = nil
	return store(old)
end

function FakeDataStore:ListKeysAsync()
	self:charge("list")
	local out = {}
	local n = 0
	for key in pairs(self.keys) do
		n = n + 1
		out[n] = key
	end
	table.sort(out)
	return out
end

-- ---------------------------------------------------------- MemoryStore

local FakeHashMap = {}
FakeHashMap.__index = FakeHashMap

local function newHashMap(env, name)
	return setmetatable({ env = env, name = name, data = {}, expiry = {} }, FakeHashMap)
end

function FakeHashMap:charge(kind, units)
	local env = self.env
	local stats = env.stats.memory
	stats[kind] = (stats[kind] or 0) + 1
	stats.total = stats.total + 1
	stats.units = stats.units + (units or 1)
	local inject = env.inject
	if nextRandom(env.rng) * 1000 < (inject.memoryThrottlePerMille or 0) then
		stats.injectedThrottles = stats.injectedThrottles + 1
		error("PartitionRequestsOverLimit: RequestThrottled", 0)
	end
	if stats.estimatedBytes > (inject.memoryQuotaBytes or math.huge) then
		error("TotalMemoryOverLimit: MemoryStore quota exceeded", 0)
	end
end

function FakeHashMap:live(key)
	local until_ = self.expiry[key]
	if until_ ~= nil and self.env.clock.now >= until_ then
		self.data[key] = nil
		self.expiry[key] = nil
		return false
	end
	return self.data[key] ~= nil
end

function FakeHashMap:GetAsync(key)
	self:charge("get", 1)
	if not self:live(key) then
		return nil
	end
	return store(self.data[key])
end

-- EXPIRATION IS NOT OPTIONAL. The real signature is
-- SetAsync(key, value, expiration) with expiration in seconds, capped at
-- 3 888 000 (45 days). This fake used to default a missing ttl to 45
-- seconds, so a call that simply forgot the argument worked in the suite and
-- would have thrown in production -- and, worse, a key meant to live for
-- hours would have evaporated in under a minute.
local MEMORY_MAX_TTL = 3888000

local function requireTtl(where, ttl)
	if ttl == nil then
		error(where .. ": expiration is a required argument", 0)
	end
	if type(ttl) ~= "number" or ttl ~= ttl or ttl <= 0 then
		error(where .. ": expiration must be a positive number", 0)
	end
	if ttl > MEMORY_MAX_TTL then
		error(where .. ": expiration exceeds the 45-day maximum (3888000 s)", 0)
	end
end

function FakeHashMap:SetAsync(key, value, ttl)
	self:charge("set", 2)
	requireTtl("MemoryStoreHashMap:SetAsync", ttl)
	self.data[key] = store(value)
	self.expiry[key] = self.env.clock.now + ttl
	return true
end

-- `HashMap:UpdateAsync` costs at least two request units and counts against
-- both the read and the write budget. Modelled, because the whole MemoryStore
-- design in doc 03 turns on that fact.
function FakeHashMap:UpdateAsync(key, transform, ttl)
	self:charge("update", 2)
	requireTtl("MemoryStoreHashMap:UpdateAsync", ttl)
	local old = nil
	if self:live(key) then
		old = store(self.data[key])
	end
	-- MemoryStore re-runs a contended transform too: "the transform function
	-- is invoked again with the most recent item value... This cycle repeats
	-- until the value is saved successfully or the transform returns nil."
	local retries = self.env.inject.transformRetries or 1
	local new
	for _ = 1, retries do
		local current = nil
		if self:live(key) then
			current = store(self.data[key])
		end
		new = transform(current)
	end
	new = transform(old)
	if new == nil then
		return nil
	end
	self.data[key] = store(new)
	self.expiry[key] = self.env.clock.now + ttl
	return store(new)
end

function FakeHashMap:RemoveAsync(key)
	self:charge("remove", 1)
	self.data[key] = nil
	self.expiry[key] = nil
	return true
end

local FakeQueue = {}
FakeQueue.__index = FakeQueue

local function newQueue(env, name)
	return setmetatable({ env = env, name = name, items = {}, nextId = 1, invisible = {} }, FakeQueue)
end

function FakeQueue:AddAsync(value, ttl, priority)
	local stats = self.env.stats.memory
	stats.queueAdd = (stats.queueAdd or 0) + 1
	stats.total = stats.total + 1
	self.items[#self.items + 1] = { id = self.nextId, value = store(value), expires = self.env.clock.now + (ttl or 300) }
	self.nextId = self.nextId + 1
	return true
end

function FakeQueue:ReadAsync(count, allOrNothing, waitTimeout)
	local stats = self.env.stats.memory
	stats.queueRead = (stats.queueRead or 0) + 1
	stats.total = stats.total + 1
	local out = {}
	local ids = {}
	local n = 0
	for i = 1, #self.items do
		if n >= (count or 1) then
			break
		end
		local item = self.items[i]
		if item.expires > self.env.clock.now then
			n = n + 1
			out[n] = store(item.value)
			ids[n] = item.id
		end
	end
	if n == 0 then
		return nil, nil
	end
	return out, table.concat(ids, ",")
end

function FakeQueue:RemoveAsync(id)
	local stats = self.env.stats.memory
	stats.queueRemove = (stats.queueRemove or 0) + 1
	stats.total = stats.total + 1
	local keep = {}
	local wanted = {}
	for part in string.gmatch(tostring(id), "[^,]+") do
		wanted[tonumber(part)] = true
	end
	for i = 1, #self.items do
		if not wanted[self.items[i].id] then
			keep[#keep + 1] = self.items[i]
		end
	end
	self.items = keep
	return true
end

-- ------------------------------------------------------------ the DataModel

local function newStats()
	return {
		dataStore = {
			get = 0,
			set = 0,
			update = 0,
			remove = 0,
			list = 0,
			total = 0,
			injectedConflicts = 0,
			injectedThrottles = 0,
			injectedQuota = 0,
			budgetBlocks = 0,
		},
		memory = {
			get = 0,
			set = 0,
			update = 0,
			remove = 0,
			queueAdd = 0,
			queueRead = 0,
			queueRemove = 0,
			total = 0,
			units = 0,
			estimatedBytes = 0,
			injectedThrottles = 0,
		},
		scheduler = { waits = 0, spawns = 0, delays = 0, secondsWaited = 0 },
	}
end

-- opts:
--   startTime  virtual UTC seconds (default: the tide epoch plus a bit)
--   seed       failure-injection seed
--   players    headcount used for the per-server budget formula
--   inject     { conflictPerMille, throttlePerMille, quotaPerMille,
--                memoryThrottlePerMille, memoryQuotaBytes }
--   enforceBudget  default true
function FakePlatform.new(opts)
	local o = opts or {}
	local env = {}
	env.clock = { now = o.startTime or 1767225600 }
	env.rng = lcg(o.seed or 12345)
	env.inject = o.inject or {}
	env.stats = newStats()
	env.playerCount = o.players or 1
	env.enforceBudget = o.enforceBudget ~= false
	env.dataStores = {}
	env.hashMaps = {}
	env.queues = {}
	env.timers = {}
	env.closeHandlers = {}
	env.players = {}
	env.playerList = {}

	-- Per-server, per-minute allowances, re-verified 2026-10-01.
	function env:budgetCap(kind)
		if kind == "list" then
			return 5 + self.playerCount * 2
		end
		return 60 + self.playerCount * 40
	end

	env.budgetSpent = { get = 0, set = 0, update = 0, remove = 0, list = 0 }
	env.budgetWindowStart = env.clock.now

	function env:rollBudgetWindow()
		if self.clock.now - self.budgetWindowStart >= 60 then
			self.budgetWindowStart = self.clock.now
			for k in pairs(self.budgetSpent) do
				self.budgetSpent[k] = 0
			end
		end
	end

	function env:spendBudget(kind)
		self:rollBudgetWindow()
		-- UpdateAsync decrements BOTH the read and the write budget. This is
		-- the single most consequential quota fact for TIDEKEEPER, because
		-- every write we make is an UpdateAsync.
		if kind == "update" then
			self.budgetSpent.get = self.budgetSpent.get + 1
			self.budgetSpent.set = self.budgetSpent.set + 1
		else
			self.budgetSpent[kind] = (self.budgetSpent[kind] or 0) + 1
		end
	end

	function env:remainingBudget(kind)
		self:rollBudgetWindow()
		local cap = self:budgetCap(kind)
		local spent = self.budgetSpent[kind] or 0
		local left = cap - spent
		if left < 0 then
			return 0
		end
		return left
	end

	-- ------------------------------------------------------- services

	local DataStoreService = {}
	function DataStoreService:GetDataStore(name)
		local existing = env.dataStores[name]
		if existing == nil then
			existing = newDataStore(env, name)
			env.dataStores[name] = existing
		end
		return existing
	end
	function DataStoreService:GetRequestBudgetForRequestType(requestType)
		if not env.enforceBudget then
			return 1000
		end
		local kind = "get"
		if requestType == "UpdateAsync" or requestType == "SetIncrementAsync"
			or requestType == "StandardWrite" then
			kind = "set"
		elseif requestType == "StandardRemove" then
			kind = "remove"
		elseif requestType == "ListAsync" or requestType == "StandardList" then
			kind = "list"
		elseif requestType == "StandardRead" then
			kind = "get"
		end
		local left = env:remainingBudget(kind)
		if left <= 0 then
			env.stats.dataStore.budgetBlocks = env.stats.dataStore.budgetBlocks + 1
		end
		return left
	end
	function DataStoreService:SetRateLimitForRequestType() end

	local MemoryStoreService = {}
	function MemoryStoreService:GetHashMap(name)
		local existing = env.hashMaps[name]
		if existing == nil then
			existing = newHashMap(env, name)
			env.hashMaps[name] = existing
		end
		return existing
	end
	function MemoryStoreService:GetSortedMap(name)
		return self:GetHashMap("sorted:" .. name)
	end
	function MemoryStoreService:GetQueue(name, invisibility)
		local existing = env.queues[name]
		if existing == nil then
			existing = newQueue(env, name)
			env.queues[name] = existing
		end
		return existing
	end

	-- A Players service with real-enough signals. The signal implementation
	-- is synchronous, which is what makes the whole test deterministic.
	local function newSignal()
		local handlers = {}
		return {
			Connect = function(_, fn)
				handlers[#handlers + 1] = fn
				return {
					Disconnect = function()
						for i = 1, #handlers do
							if handlers[i] == fn then
								table.remove(handlers, i)
								break
							end
						end
					end,
				}
			end,
			Fire = function(_, ...)
				for i = 1, #handlers do
					handlers[i](...)
				end
			end,
		}
	end

	local Players = {}
	Players.PlayerAdded = newSignal()
	Players.PlayerRemoving = newSignal()
	function Players:GetPlayers()
		local out = {}
		for i = 1, #env.playerList do
			out[i] = env.playerList[i]
		end
		return out
	end

	env.PlayersService = Players

	local RunService = {}
	RunService.Heartbeat = newSignal()
	function RunService:IsStudio()
		return false
	end
	function RunService:IsServer()
		return true
	end
	env.RunService = RunService

	local PolicyService = {}
	function PolicyService:GetPolicyInfoForPlayerAsync(player)
		return {
			ArePaidRandomItemsRestricted = true,
			IsPaidItemTradingAllowed = false,
			IsSubjectToChinaPolicies = false,
			AllowedExternalLinkReferences = {},
		}
	end

	local services = {
		DataStoreService = DataStoreService,
		MemoryStoreService = MemoryStoreService,
		Players = Players,
		RunService = RunService,
		PolicyService = PolicyService,
		ReplicatedStorage = stubInstance("ReplicatedStorage"),
		ServerStorage = stubInstance("ServerStorage"),
		ServerScriptService = stubInstance("ServerScriptService"),
		HttpService = { GenerateGUID = function() return "00000000" end },
	}
	env.services = services

	local gameObject = {}
	gameObject.JobId = o.jobId or "fake-job-0001"
	function gameObject:GetService(name)
		local svc = services[name]
		if svc == nil then
			error("FakePlatform: no fake for service " .. tostring(name), 0)
		end
		return svc
	end
	function gameObject:BindToClose(fn)
		env.closeHandlers[#env.closeHandlers + 1] = fn
	end
	env.game = gameObject

	-- ------------------------------------------------------ the clock

	-- `task.wait` advances virtual time and fires anything scheduled in the
	-- interval. Nothing ever actually sleeps, so the adapter's real backoff
	-- (0, 0.5, 1.5, 4, 9 seconds) runs at full speed and is still measured.
	function env:advance(seconds)
		local target = self.clock.now + (seconds or 0)
		while true do
			local soonest = nil
			local index = nil
			for i = 1, #self.timers do
				local t = self.timers[i]
				if t.at <= target and (soonest == nil or t.at < soonest) then
					soonest = t.at
					index = i
				end
			end
			if index == nil then
				break
			end
			local timer = table.remove(self.timers, index)
			self.clock.now = timer.at
			timer.fn()
		end
		self.clock.now = target
		return self.clock.now
	end

	function env:wait(seconds)
		self.stats.scheduler.waits = self.stats.scheduler.waits + 1
		self.stats.scheduler.secondsWaited = self.stats.scheduler.secondsWaited + (seconds or 0)
		return self:advance(seconds or 0)
	end

	env.task = {
		wait = function(seconds)
			return env:wait(seconds)
		end,
		spawn = function(fn, ...)
			env.stats.scheduler.spawns = env.stats.scheduler.spawns + 1
			fn(...)
		end,
		delay = function(seconds, fn, ...)
			env.stats.scheduler.delays = env.stats.scheduler.delays + 1
			local args = { ... }
			env.timers[#env.timers + 1] = {
				at = env.clock.now + (seconds or 0),
				fn = function()
					fn(table.unpack(args))
				end,
			}
		end,
		defer = function(fn, ...)
			fn(...)
		end,
	}

	function env:now()
		return self.clock.now
	end

	-- ------------------------------------------------------- players

	function env:addPlayer(userId, name)
		local player = { UserId = userId, Name = name or ("p" .. tostring(userId)) }
		env.players[userId] = player
		env.playerList[#env.playerList + 1] = player
		env.PlayersService.PlayerAdded:Fire(player)
		return player
	end

	function env:removePlayer(userId)
		local player = env.players[userId]
		if player == nil then
			return nil
		end
		env.PlayersService.PlayerRemoving:Fire(player)
		env.players[userId] = nil
		for i = 1, #env.playerList do
			if env.playerList[i] == player then
				table.remove(env.playerList, i)
				break
			end
		end
		return player
	end

	-- One Heartbeat, the way CadenceService sees it.
	function env:heartbeat(dt)
		env:advance(dt or 0.0166)
		env.RunService.Heartbeat:Fire(dt or 0.0166)
	end

	function env:close()
		for i = 1, #env.closeHandlers do
			env.closeHandlers[i]()
		end
	end

	function env:totalRequests()
		return env.stats.dataStore.total
	end

	return env
end

-- Install the fake as the ambient globals the game expects. Called before
-- any module is required, because every module reads `game` at load time.
function FakePlatform.install(env)
	game = env.game
	task = env.task
	-- THE REAL Enum.DataStoreRequestType, and nothing else.
	--
	-- This table used to contain `RemoveAsync`, which DOES NOT EXIST on the
	-- real enum. It had been invented here to match what the adapter
	-- happened to ask for, so the fake agreed with its author by
	-- construction -- and a real Studio run then produced, once every five
	-- seconds forever:
	--
	--   slot io task exchange.reap errored: RemoveAsync is not a valid
	--   member of "Enum.DataStoreRequestType" (x24)
	--
	-- Members below are the published list; the remove-shaped ones are
	-- `StandardRemove` (modern) and `SetIncrementAsync` (legacy, which the
	-- reference says covers RemoveAsync).
	local requestTypes = {
		"GetAsync", "SetIncrementAsync", "UpdateAsync", "GetSortedAsync",
		"SetIncrementSortedAsync", "OnUpdate", "ListAsync", "GetVersionAsync",
		"RemoveVersionAsync", "StandardRead", "StandardWrite", "StandardList",
		"StandardRemove", "OrderedRead", "OrderedWrite", "OrderedList",
		"OrderedRemove",
	}
	local requestTypeTable = {}
	for _, name in ipairs(requestTypes) do
		requestTypeTable[name] = name
	end
	-- Roblox THROWS on a missing Enum member. So does this now: a fake that
	-- silently answers nil for a name the platform does not have is how an
	-- invented enum member survives eleven iterations of green tests (D54).
	setmetatable(requestTypeTable, {
		__index = function(_, key)
			error(tostring(key) .. ' is not a valid member of "Enum.DataStoreRequestType"', 0)
		end,
	})

	Enum = {
		DataStoreRequestType = requestTypeTable,
	}
	Instance = {
		new = function(className)
			return { ClassName = className, Name = "", Parent = nil }
		end,
	}
	-- Anything that forgot to take an injected clock still gets virtual time
	-- rather than wall time, so a missed injection shows up as a wrong
	-- number rather than as a flaky test.
	os.time = function()
		return math.floor(env.clock.now)
	end
	os.clock = function()
		return env.clock.now
	end
	return env
end

return FakePlatform
