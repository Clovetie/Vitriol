--!strict
-- HealthService.luau
-- Location: ServerStorage > Vitriol > Services > HealthService  (ModuleScript)
-- Purpose:  The body's ledger: per-player health, the wound list, bleed drain, clot
--            recovery, and the noise a wounded body makes. It is the WP4 skeleton for
--            the survival loop - the full movement/stamina/crafting state is
--            SurvivalService's (WP8) - and it exists now because three other systems
--            read wounds: the creature smells blood (docs/02 §2), bleeding is audible
--            (docs/05 §3), and a severed limb bleeds worse (docs/04 §4).
--
--            SINGLE WRITER OF HUMANOID HEALTH FOR WOUNDS. The frame slot diffs
--            Humanoid.Health against its own last read, so damage that arrived through
--            some other path (a fall, a vehicle, a scripted sequence) is converted
--            into a wound exactly once, and the bleed drain this module applies is
--            subtracted from the same diff so it cannot feed itself. Registering
--            Humanoid.HealthChanged instead would work too; the diff runs on the
--            cadence so N players cost one slot, not N connections, and a player who
--            joins mid-frame cannot be missed.
--
--            NO HUD, NO UI. Health and wounds are STATE; SurvivalHUD draws them
--            (docs/01 §11). Bleeding is signalled diegetically - a drip cue and a
--            scent impulse - never with a vignette or a counter (docs/05 §7).
-- Requires: Config/SurvivalConfig, Config/MonsterConfig, Config/GameConfig
-- Used by:  Bootstrap, CreatureService (scent scale), DamageRegistry (later), Clients

local HealthService = {}
HealthService.__index = HealthService

local LAZY = {}
local function survivalConfig(): any
	if LAZY.SurvivalConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.SurvivalConfig = require(ReplicatedStorage.Vitriol.Config.SurvivalConfig)
	end
	return LAZY.SurvivalConfig
end
local function gameConfig(): any
	if LAZY.GameConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.GameConfig = require(ReplicatedStorage.Vitriol.Config.GameConfig)
	end
	return LAZY.GameConfig
end

local DEFAULT_WOUND = "Laceration" -- an unclassified hit still has to bleed somewhere
local ZERO = 0
local NEGLIGIBLE_HEALTH = 1e-4 -- a health diff smaller than this is float dust, not damage

-- init(svc, services) -> ()
-- services = { Players, Cadence, Noise, Time, Config, Survival, Logger }
function HealthService.init(svc: any, services: any): ()
	svc.Config = services.Config or gameConfig()
	svc.Survival = services.Survival or survivalConfig()
	svc.Health = svc.Survival.Health
	svc.Emission = svc.Survival.Emission
	svc.Players = services.Players
	svc.Cadence = services.Cadence
	svc.Noise = services.Noise
	svc.Time = services.Time
	svc.log = services.Logger

	svc.states = {}
	svc.count = 0
	svc.running = false
	svc.connections = {}
end

-- start(svc) -> ()
function HealthService:start(): ()
	if self.running then
		return
	end
	self.running = true
	local players = self.Players
	if players then
		self.connections[#self.connections + 1] = players.PlayerAdded:Connect(function(player)
			self:observe(player)
		end)
		self.connections[#self.connections + 1] = players.PlayerRemoving:Connect(function(player)
			self:forget(player)
		end)
		for _, player in ipairs(players:GetPlayers()) do
			self:observe(player)
		end
	end
	local cadence = self.Cadence
	if cadence then
		self.frameSlot = cadence:register({
			Name = "Health:Damage",
			-- Frame cadence, because "did I just get hit" has to be answered in the
			-- same frame the creature sees the flinch; the whole slot is one number
			-- read per living player.
			PeriodSeconds = 0,
			BudgetMs = self.Config.Budgets.FrameShares.Health,
			Run = function(dt)
				self:trackDamage(dt)
			end,
		})
		self.slowSlot = cadence:register({
			Name = "Health:Slow",
			PeriodSeconds = 1 / self.Config.Ticks.SlowHz,
			BudgetMs = self.Config.Budgets.SlowShares.Health,
			Run = function(dt)
				self:tickBleed(dt)
			end,
		})
	end
end

-- observe(svc, player) -> state
-- CharacterAdded rather than a health observation at join: the humanoid does not exist
-- until the character replicates, and a service that assumes it does is the classic
-- nil-deref on a slow join.
function HealthService:observe(player: any): any
	local state = self.states[player.UserId]
	if state == nil then
		self.count = self.count + 1
		state = {
			UserId = player.UserId,
			Name = player.Name,
			wounds = {},
			woundCount = 0,
			health = 0,
			maxHealth = 0,
			bleedRate = 0,
			scentScale = 1,
			applied = 0,
			dripLeft = 0,
			metersAllowRegen = false,
			incapacitated = false,
			dead = false,
			humanoid = nil,
		}
		self.states[player.UserId] = state
	end
	if state.connected == nil then
		state.connected = true
		-- One CharacterAdded connection per player, not per respawn: a reconnecting
		-- player re-enters observe(), and a second connection would attach twice.
		self.connections[#self.connections + 1] = player.CharacterAdded:Connect(function(character)
			self:attach(state, character)
		end)
	end
	if player.Character then
		self:attach(state, player.Character)
	end
	return state
end

-- attach(svc, state, character) -> ()
function HealthService:attach(state: any, character: any): ()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	state.character = character
	state.humanoid = humanoid
	if humanoid then
		state.maxHealth = humanoid.MaxHealth
		state.health = humanoid.Health
		state.root = humanoid.RootPart
	end
end

-- forget(svc, player) -> ()
function HealthService:forget(player: any): ()
	local state = self.states[player.UserId]
	if state == nil then
		return
	end
	-- The corpse scent is already in the field (emitted at death, with its own
	-- halflife), so dropping the state does not silence the body.
	self.states[player.UserId] = nil
	self.count = self.count - 1
end

-- addWound(svc, player, kind, multiplier?) -> state?
-- The entry point the combat path uses. `multiplier` is the damage-scaled severity
-- (docs/04 §4: a severing hit bleeds worse than the same hit through armour).
function HealthService:addWound(player: any, kind: string, multiplier: number?): any
	local state = self.states[player.UserId]
	if state == nil or state.dead then
		return nil
	end
	local wound = self.Health.Wounds[kind]
	if wound == nil then
		-- An unknown injury kind is a content bug, and the honest response is to treat
		-- it as the common case rather than invent a new curve nobody tuned.
		kind = DEFAULT_WOUND
		wound = self.Health.Wounds[kind]
	end
	local scale = multiplier or 1
	local now = self:now()
	state.woundCount = state.woundCount + 1
	state.wounds[state.woundCount] = {
		Kind = kind,
		BleedRate = wound.BleedRate * scale,
		ScentRate = wound.ScentRate * scale,
		ClotAt = now + wound.ClotSeconds,
		TreatSeconds = wound.TreatSeconds,
		Region = nil, -- set by the severing path (docs/04 §4) when a limb goes
		At = now,
	}
	self:recomputeBleed(state)
	return state
end

-- recomputeBleed(svc, state) -> ()
-- One pass over the wound list producing the two numbers everything else reads. This
-- is called on wound changes only, never per frame.
function HealthService:recomputeBleed(state: any): ()
	local rate = 0
	local scent = 0
	local wounds = state.wounds
	for i = 1, state.woundCount do
		local w = wounds[i]
		if w ~= nil then
			rate = rate + w.BleedRate
			scent = scent + w.ScentRate
		end
	end
	state.bleedRate = rate
	-- docs/05 §3: a body bleeding at rate r smells like 1 + 6r. The multiplier is
	-- already severity-scaled, so two shallow cuts smell worse than one deep one,
	-- which is the right instinct for a predator.
	state.scentScale = 1 + self.Emission.BloodScentPerRate * scent
end

-- trackDamage(svc, dt) -> ()
-- Frame slot: diff each player's health against the last read.
function HealthService:trackDamage(dt: number): ()
	for _, state in pairs(self.states) do
		local humanoid = state.humanoid
		if humanoid ~= nil then
			local health = humanoid.Health
			local delta = state.health - health - state.applied
			state.health = health
			state.applied = 0
			if delta > NEGLIGIBLE_HEALTH then
				-- Damage from somewhere else. Attribute it to a wound so the bleed,
				-- the smell and the creature's interest all follow automatically.
				self:onDamage(state, delta)
			end
			if health <= 0 and not state.dead then
				self:onDeath(state)
			elseif health <= self.Health.IncapacitatedThreshold and not state.dead and not state.incapacitated then
				self:onIncapacitate(state)
			end
		end
	end
end

-- onDamage(svc, state, amount) -> ()
-- The mapping from "health went down" to "which wound": severity decides. Under the
-- incapacitated threshold a hit is a Bruise (it hurts, it does not open you); below
-- half health it is a Puncture; a big single hit is an Avulsion, which is the state
-- that ends runs.
function HealthService:onDamage(state: any, amount: number): ()
	local kind = DEFAULT_WOUND
	if amount >= self.Health.Max * 0.34 then
		kind = "Avulsion"
	elseif state.health < self.Health.Max * 0.5 then
		kind = "Puncture"
	elseif amount < self.Health.Max * 0.06 then
		kind = "Bruise"
	end
	self:addWoundByUserId(state.UserId, kind, 1)
end

-- addWoundByUserId(svc, userId, kind, multiplier) -> ()
-- The Player-free form, because the damage path has the state and not the player.
function HealthService:addWoundByUserId(userId: number, kind: string, multiplier: number?): ()
	local state = self.states[userId]
	if state == nil or state.dead then
		return
	end
	local wound = self.Health.Wounds[kind]
	if wound == nil then
		kind = DEFAULT_WOUND
		wound = self.Health.Wounds[kind]
	end
	local scale = multiplier or 1
	local now = self:now()
	state.woundCount = state.woundCount + 1
	state.wounds[state.woundCount] = {
		Kind = kind,
		BleedRate = wound.BleedRate * scale,
		ScentRate = wound.ScentRate * scale,
		ClotAt = now + wound.ClotSeconds,
		TreatSeconds = wound.TreatSeconds,
		Region = nil,
		At = now,
	}
	self:recomputeBleed(state)
end

-- limbSevered(svc, userId, regionName) -> ()
-- The seam docs/04 §4 asks for: a severed limb is not just damage, it re-ranks the
-- worst wound so a leg lost bleeds like the wound it replaced, not like a scratch.
function HealthService:limbSevered(userId: number, regionName: any): ()
	local state = self.states[userId]
	if state == nil then
		return
	end
	for i = 1, state.woundCount do
		local w = state.wounds[i]
		if w ~= nil and w.Region == nil then
			w.Region = regionName
			w.BleedRate = w.BleedRate * self.Health.SeveredBleedMultiplier
			w.ScentRate = w.ScentRate * self.Health.SeveredBleedMultiplier
			break
		end
	end
	self:recomputeBleed(state)
end

-- tickBleed(svc, dt) -> ()
-- Slow slot: drain, clot, heal. All three are per-second rates from config, so the
-- only thing in here is arithmetic on one state table per player.
function HealthService:tickBleed(dt: number): ()
	local now = self:now()
	local health = self.Health
	for _, state in pairs(self.states) do
		local humanoid = state.humanoid
		if humanoid ~= nil and not state.dead then
			if state.bleedRate > 0 then
				local drain = state.bleedRate * dt
				state.applied = state.applied + drain
				humanoid.Health = humanoid.Health - drain
				if humanoid.Health <= 0 then
					self:onDeath(state)
				end
				self:emitBlood(state, dt)
			end
			-- Clotting: a wound stops on its own after ClotSeconds, which is why a
			-- bandage is a shortcut and not a requirement (docs/05 §5).
			local survived = 0
			for i = 1, state.woundCount do
				local w = state.wounds[i]
				if w ~= nil and now < w.ClotAt then
					survived = survived + 1
					state.wounds[survived] = w
				end
			end
			if survived < state.woundCount then
				for i = survived + 1, state.woundCount do
					state.wounds[i] = nil
				end
				state.woundCount = survived
				self:recomputeBleed(state)
			end
			if state.bleedRate == 0 and state.metersAllowRegen and state.health > health.IncapacitatedThreshold and state.health < state.maxHealth then
				-- Regen needs no bleeding AND a fed, hydrated body (docs/05 §2). The
				-- meters belong to SurvivalService (WP8), so this module takes a flag
				-- instead of reading state it does not own - and the flag defaults to
				-- false, so an unmet precondition cannot grant a bonus.
				local heal = health.RegenPerSecond * dt
				state.applied = state.applied - heal
				humanoid.Health = math.min(state.maxHealth, humanoid.Health + heal)
			end
		end
	end
end

-- emitBlood(svc, state, dt) -> ()
-- Scent at full rate every slow tick (the field decays it), the drip cue only every
-- BleedCueSeconds (docs/05 §3: audible inside about a stud).
function HealthService:emitBlood(state: any, dt: number): ()
	local noise = self.Noise
	local root = state.root
	if noise == nil or root == nil then
		return
	end
	local x, y, z = root.Position.X, root.Position.Y, root.Position.Z
	local now = self:now()
	-- Intensity is the bleed RATE times the config's per-rate coefficient, which is
	-- what BloodScentPerRate means; the halflife belongs to the field's channel, not
	-- to the emitter, and scaling by dt here would make the smell a function of how
	-- often the scheduler happens to wake.
	noise:emit("SCENT", x, y, z, state.bleedRate * self.Emission.BloodScentPerRate, now, {
		EmitterId = -state.UserId,
	})
	if state.dripLeft <= 0 then
		-- docs/05 §3.1's "drip audio": re-cued on a timer rather than emitted every
		-- tick, because the field decays by elapsed time and an impulse per frame
		-- would be a 60 Hz sound - and the creature's ear is not the point of a
		-- drip, the player's own is.
		state.dripLeft = self.Health.BleedCueSeconds
		noise:emit("AIR", x, y, z, self.Emission.BloodAirIntensity, now, {
			EmitterId = -state.UserId,
		})
	else
		state.dripLeft = state.dripLeft - dt
	end
end

-- onIncapacitate(svc, state) -> ()
function HealthService:onIncapacitate(state: any): ()
	state.incapacitated = true
	self:emit(state.Name .. " is incapacitated at " .. string.format("%.1f", state.health) .. " hp")
end

-- onDeath(svc, state) -> ()
-- A corpse is a scent source for the rest of the night, and the session's kill count
-- is a threat input (docs/02 §12). The state is kept until the player leaves so the
-- corpse's wound list can still be read by the butchery/carrying paths.
function HealthService:onDeath(state: any): ()
	state.dead = true
	state.bleedRate = 0
	local noise = self.Noise
	local root = state.root
	if noise ~= nil and root ~= nil then
		noise:emit("SCENT", root.Position.X, root.Position.Y, root.Position.Z, self.Emission.CorpseScent, self:now(), {
			EmitterId = -state.UserId,
			Halflife = self.Emission.CorpseScentDecaySeconds,
		})
	end
	-- NOT a session kill: the threat dial counts creatures the group has killed
	-- (docs/02 §12), so a player dying must never make the hunt harder.
	self:emit(state.Name .. " died")
end

-- metersAllowRegen(svc, userId, ok) -> ()
-- The seam SurvivalService (WP8) drives: "this player is fed enough to heal".
function HealthService:metersAllowRegen(userId: number, ok: boolean): ()
	local state = self.states[userId]
	if state ~= nil then
		state.metersAllowRegen = ok and true or false
	end
end

-- scentScale(svc, userId) -> number
-- What Senses multiply a smell check by (docs/02 §2: blood x6 at a heavy rate).
function HealthService:scentScale(userId: number): number
	local state = self.states[userId]
	if state == nil then
		return 1
	end
	return state.scentScale
end

-- snapshot(svc) -> table
function HealthService:snapshot(): any
	local out = {}
	for userId, state in pairs(self.states) do
		out[#out + 1] = {
			userId = userId,
			name = state.Name,
			health = state.health,
			wounds = state.woundCount,
			bleedRate = state.bleedRate,
			scentScale = state.scentScale,
			dead = state.dead,
		}
	end
	return { players = out, count = self.count }
end

-- now(svc) -> seconds
-- Virtual-clock-safe: TimeService owns elapsed time, and asking it keeps HealthService
-- from being a second clock (docs/06 §9.3). os.clock would also be a syscall in a
-- slot that runs on the frame cadence.
function HealthService:now(): number
	local time = self.Time
	if time then
		return time.elapsedTotal
	end
	return ZERO
end

function HealthService:emit(message: string): ()
	local sink = self.log
	if sink then
		sink("info", message)
	end
end

-- stop(svc) -> ()
function HealthService:stop(): ()
	self.running = false
	local cadence = self.Cadence
	if cadence then
		cadence:unregister(self.frameSlot)
		cadence:unregister(self.slowSlot)
	end
	self.frameSlot = nil
	self.slowSlot = nil
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

return HealthService
