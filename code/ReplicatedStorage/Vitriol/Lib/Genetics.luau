--!strict
-- Genetics.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Genetics  (ModuleScript)
-- Purpose:  Creature genome: roll, mutate, crossover, express, fitness.
--           The metabolic budget projection is what guarantees there is no such
--           thing as a monster that is good at everything (docs/02 §5.2).
--           Pure: no services, no Instances, no yields.
-- Requires: (none)  -- gene definitions are injected, so Lib stays Config-free
-- Used by:  Services/EvolutionService, Services/CreatureService

local Genetics = {}
Genetics.__index = Genetics

-- Gene definition: { name, cost, min, max, kind = "float"|"int", default }
-- `cost` is multiplied by the gene value and summed against the metabolic
-- budget. A high budget therefore cannot coexist with high everything.

-- Default definitions mirror ReplicatedStorage/Vitriol/Config/MonsterConfig.Genes
-- for the MVP archetype "Braid". Kept here so the module is testable without a
-- Config dependency; MonsterConfig is the source of truth at runtime and is
-- injected via Genetics.new().
Genetics.DEFAULT_GENES = {
	{ name = "Speed", cost = 0.14, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Strength", cost = 0.13, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Endurance", cost = 0.09, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Mass", cost = 0.12, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Adhesion", cost = 0.07, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Softness", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseVibration", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseAir", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseScent", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseThermal", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseEM", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Cunning", cost = 0.10, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Patience", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Aggression", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Metabolism", cost = 0.08, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Regeneration", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Armour", cost = 0.09, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "ShearRate", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "GripTenacity", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "TendrilLength", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "TendrilCount", cost = 0.02, min = 6, max = 14, kind = "int", default = 8 },
}

local TENDRIL_BASE = 6

local function clamp01(v: number): number
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- new(genes, opts) -> Genetics
-- opts: { budget = number, sigma = number, structuralChance = number }
function Genetics.new(genes: any, opts: any)
	local self = setmetatable({}, Genetics)
	self.genes = genes or Genetics.DEFAULT_GENES
	self.budget = (opts and opts.budget) or 0.95
	self.sigma = (opts and opts.sigma) or 0.06
	self.structuralChance = (opts and opts.structuralChance) or 0.10
	self.byName = {}
	for i = 1, #self.genes do
		local g = self.genes[i]
		self.byName[g.name] = g
	end
	return self
end

-- cost(genome) -> number
-- Total metabolic cost. Must stay <= budget.
function Genetics:cost(genome: any): number
	local total = 0
	for i = 1, #self.genes do
		local g = self.genes[i]
		local v = genome[g.name] or g.default
		if g.kind == "int" and g.name == "TendrilCount" then
			-- Extra tendrils cost; the first TENDRIL_BASE are "free" body plan.
			total += math.max(0, v - TENDRIL_BASE) * g.cost
		else
			total += v * g.cost
		end
	end
	return total
end

-- project(genome) -> genome
-- Scale the float genes down until the genome fits the budget.
--
-- The scale factor must be solved against the *variable* cost only: integer
-- genes (tendril overhead) are a fixed part of the body plan and are not scaled.
-- Scaling everything by budget/total leaves the result over budget whenever the
-- fixed overhead is non-zero, which is exactly the bug a naive implementation
-- has here.
function Genetics:project(genome: any): any
	local fixed = 0
	local variable = 0
	for i = 1, #self.genes do
		local g = self.genes[i]
		local v = genome[g.name] or g.default
		if g.kind == "int" then
			if g.name == "TendrilCount" then
				fixed += math.max(0, v - TENDRIL_BASE) * g.cost
			end
		else
			variable += v * g.cost
		end
	end

	local total = fixed + variable
	if total <= self.budget then
		return genome
	end

	local room = self.budget - fixed
	local scale = 0
	if room > 0 and variable > 0 then
		scale = room / variable
	end
	for i = 1, #self.genes do
		local g = self.genes[i]
		if g.kind ~= "int" then
			genome[g.name] = clamp01((genome[g.name] or g.default) * scale)
		end
	end
	return genome
end

-- roll(rng) -> genome
function Genetics:roll(rng: any): any
	local genome = { scars = {}, lineage = 0 }
	for i = 1, #self.genes do
		local g = self.genes[i]
		if g.kind == "int" then
			genome[g.name] = rng:int(g.min, g.max)
		else
			genome[g.name] = rng:range(g.min, g.max)
		end
	end
	return self:project(genome)
end

-- mutate(genome, rng) -> newGenome
-- Does not modify the input genome (the elite pool must stay intact).
function Genetics:mutate(genome: any, rng: any): any
	local child = { scars = {}, lineage = (genome.lineage or 0) }
	for i = 1, #self.genes do
		local g = self.genes[i]
		local v = genome[g.name] or g.default
		if g.kind == "int" then
			child[g.name] = v
		else
			child[g.name] = clamp01(v + rng:gaussian() * self.sigma)
		end
	end

	-- Structural mutation: tendril count changes. This is VISIBLE, and players
	-- noticing it is the point (docs/02 §5.4).
	if rng:chance(self.structuralChance) then
		local def = self.byName.TendrilCount
		local count = child.TendrilCount or def.default
		if rng:chance(0.5) then
			count += 1
		else
			count -= 1
		end
		if count < def.min then
			count = def.min
		elseif count > def.max then
			count = def.max
		end
		child.TendrilCount = count
	end

	-- Scars are inherited: a wounded lineage remembers what hurt it.
	if genome.scars then
		for i2 = 1, #genome.scars do
			table.insert(child.scars, genome.scars[i2])
		end
	end

	return self:project(child)
end

-- crossover(a, b, rng) -> newGenome
-- Uniform crossover biased toward the fitter parent. `fitnessA`/`fitnessB` set
-- the dominance; equal fitness gives a 50/50 split.
function Genetics:crossover(a: any, b: any, rng: any, fitnessA: number?, fitnessB: number?): any
	local fa = fitnessA or 0.5
	local fb = fitnessB or 0.5
	local domA = 0.5
	if fa + fb > 0 then
		domA = (0.5 + (fa - fb) / (fa + fb) * 0.5)
		if domA < 0.15 then
			domA = 0.15
		elseif domA > 0.85 then
			domA = 0.85
		end
	end

	local child = { scars = {}, lineage = (a.lineage or 0) }
	for i = 1, #self.genes do
		local g = self.genes[i]
		local fromA = rng:chance(domA)
		local v = (fromA and a[g.name]) or b[g.name] or g.default
		child[g.name] = v
	end

	-- Inherit scars from both parents, deduplicated.
	local seen = {}
	for _, parent in { a, b } do
		if parent.scars then
			for i2 = 1, #parent.scars do
				local s = parent.scars[i2]
				if not seen[s] then
					seen[s] = true
					table.insert(child.scars, s)
				end
			end
		end
	end

	return self:project(child)
end

-- express(genome) -> stats
-- Maps the genome onto gameplay numbers. Everything downstream reads `stats`,
-- never the raw genes, so balance changes happen in exactly one place.
function Genetics:express(genome: any): any
	local g = genome
	local function gene(name: string): number
		return g[name] or 0.5
	end

	local mass = gene("Mass")
	local count = g.TendrilCount or 8
	local tendrilLen = gene("TendrilLength")

	-- Heavier creatures haul themselves slower, but not linearly - real animals
	-- scale roughly with the cube root of mass.
	local massPenalty = 1 - 0.35 * mass
	local injury = 0
	if g.scars then
		injury = math.min(0.5, #g.scars * 0.12)
	end

	local stats = {
		-- body
		TendrilCount = count,
		JointsPerTendril = 8 + math.floor(8 * tendrilLen),
		TendrilReach = 8 + 10 * tendrilLen,
		CoreRadius = 1.1 + 0.9 * mass,
		MassKg = 120 + 480 * mass,
		ArmourMultiplier = 1 + 1.2 * gene("Armour"),

		-- movement
		HaulSpeed = (4 + 18 * gene("Speed")) * massPenalty * (1 - injury),
		SprintDuration = 2 + 6 * gene("Endurance"),
		ClimbCapable = gene("Adhesion") > 0.35,
		CanSqueezeUnderDoors = gene("Softness") > 0.55,
		CanBurrow = gene("Softness") > 0.45 and gene("Adhesion") > 0.3,

		-- senses (effective range in studs)
		SenseRange = {
			VIBRATION = 45 + 95 * gene("SenseVibration"),
			AIR = 40 + 80 * gene("SenseAir"),
			SCENT = 20 + 55 * gene("SenseScent"),
			THERMAL = 8 + 12 * gene("SenseThermal"),
			EM = 30 + 110 * gene("SenseEM"),
			PRESSURE = 4 + 4 * gene("SenseThermal"),
		},
		SenseAcuity = {
			VIBRATION = clamp01(0.25 + 0.75 * gene("SenseVibration")),
			AIR = clamp01(0.25 + 0.75 * gene("SenseAir")),
			SCENT = clamp01(0.25 + 0.75 * gene("SenseScent")),
			THERMAL = clamp01(0.25 + 0.75 * gene("SenseThermal")),
			EM = clamp01(0.25 + 0.75 * gene("SenseEM")),
			PRESSURE = 0.5,
		},

		-- feeding / killing
		ShearHz = 6 + 8 * gene("ShearRate"),
		TenderizeRate = 0.6 + 1.4 * gene("ShearRate"),
		GrabRadius = 2.5 + 2.5 * tendrilLen,
		EscapeMashThreshold = 30 + 70 * gene("GripTenacity"),
		CoilTurns = 2 + math.floor(4 * gene("GripTenacity")),
		MetabolismDrain = 0.5 + 1.0 * gene("Metabolism") + 0.25 * mass,
		RegenRate = 0.2 + 1.6 * gene("Regeneration"),

		-- temperament source values
		ConfidenceFloor = 0.2 + 0.3 * gene("Aggression"),
		CommitTime = 0.8 + 1.2 * gene("Aggression"),
		Injury = injury,
	}

	stats.Temperament = Genetics.temperament(genome, stats)
	return stats
end

-- temperament(genome, stats) -> { [action] = instinctScore }
-- Instinct priors from docs/02-MONSTER-DESIGN.md §6.1. These are the creature's
-- *body's opinion*; Policy adds the learned Q on top (docs/02 §6.2), which is how
-- a fast, strong creature can still learn that stalking pays.
function Genetics.temperament(genome: any, stats: any): any
	local function gene(name: string): number
		return genome[name] or 0.5
	end
	local injury = (stats and stats.Injury) or 0
	local speed = gene("Speed")
	local strength = gene("Strength")
	local mass = gene("Mass")
	local cunning = gene("Cunning")
	local patience = gene("Patience")
	local aggression = gene("Aggression")
	local endurance = gene("Endurance")
	local adhesion = gene("Adhesion")
	local softness = gene("Softness")
	local armour = gene("Armour")

	return {
		CHARGE = 0.45 * speed + 0.35 * strength + 0.20 * aggression,
		STALK = 0.35 * patience + 0.30 * cunning + 0.20 * (1 - aggression) + 0.15 * (1 - mass),
		AMBUSH = 0.40 * patience + 0.30 * cunning + 0.20 * speed + 0.10 * adhesion,
		BREACH = 0.55 * strength + 0.30 * mass + 0.15 * armour,
		LURE = 0.65 * cunning + 0.20 * patience + 0.15 * (1 - aggression),
		BURROW = 0.50 * softness + 0.30 * adhesion + 0.20 * cunning,
		FLUSH = 0.40 * strength + 0.35 * aggression + 0.25 * speed,
		CIRCLE = 0.45 * speed + 0.30 * cunning + 0.25 * adhesion,
		FEIGN = 0.60 * cunning + 0.30 * patience + 0.10 * (1 - mass),
		INTERCEPT = 0.40 * cunning + 0.35 * speed + 0.25 * patience,
		RETREAT = 0.40 * (1 - endurance) + 0.30 * injury + 0.30 * (1 - aggression),
	}
end

-- logPrior(temperament) -> { [action] = number }
-- Converted to log space because Policy ADDS it to Q values (docs/02 §6.2).
function Genetics.logPrior(temperament: any): any
	local out = {}
	for action, score in pairs(temperament) do
		local s = score
		if s < 0.02 then
			s = 0.02
		elseif s > 1 then
			s = 1
		end
		out[action] = math.log(s)
	end
	return out
end

-- fitness(genome, record) -> number
-- record: { kills, grabSeconds, damageDealt, damageTaken, died, survived }
function Genetics:fitness(genome: any, record: any): number
	local r = record or {}
	local kills = r.kills or 0
	local grabSeconds = r.grabSeconds or 0
	local damageDealt = r.damageDealt or 0
	local damageTaken = r.damageTaken or 0
	local died = r.died and 1 or 0
	local survived = r.survived and 1 or 0

	local f = 3.0 * kills
	f += 1.0 * (grabSeconds / 60)
	f += 0.5 * (damageDealt / 100)
	f -= 1.5 * (damageTaken / 100)
	f -= 0.8 * died
	f += 0.3 * survived

	-- A wounded-but-alive creature is not punished twice; scars already carry it.
	return f
end

return Genetics
