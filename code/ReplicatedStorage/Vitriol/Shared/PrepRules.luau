--!strict
-- Pure daytime-preparation cost rules. The transaction, votes, shared fade and
-- authoritative clock jump belong to server services; this module performs no
-- mutation and creates no Instances. It is not yet wired into live gameplay.
local PrepRules = {}

-- Costs at main's 210-second Day. All successful Day/Dawn preparation steps,
-- including collecting the fuel can, will use the same co-op vote window.
PrepRules.ReferenceDaySeconds = 210
PrepRules.VoteWindowSeconds = 3 -- real seconds, even with accelerated Studio timing
PrepRules.MaximumHelperDiscountSeconds = 2
PrepRules.BaseSeconds = {
	TakeFuel = 4,
	PowerGarage = 12,
	PrimeBell = 8,
	BoardGarage = 20,
	RepairStationFloodlight = 16,
	RepairGarageLight = 16,
	CoverHouse01Table = 8,
	CoverHouse01Closet = 12,
	CoverHouse02Table = 8,
	CoverHouse02Closet = 12,
}

-- Each OTHER living, nearby consenting helper reduces the base by one real
-- second, capped at two helpers. Rescale the NET cost and discount together:
-- 20 seconds at 210-second Day becomes 20/21 seconds at test Day = 10 seconds.
-- 'remaining' is the Day budget left, not elapsed time in the current phase.
function PrepRules.cost(action: string, helpers: number, daySeconds: number, remaining: number): number?
	local base = PrepRules.BaseSeconds[action]
	if base == nil or type(helpers) ~= "number" or type(daySeconds) ~= "number"
		or type(remaining) ~= "number" or helpers ~= helpers or daySeconds ~= daySeconds
		or remaining ~= remaining or helpers < 0 or daySeconds <= 0 or remaining < 0 then
		return nil
	end
	local discount = math.min(PrepRules.MaximumHelperDiscountSeconds, math.floor(helpers))
	local seconds = (base - discount) * (daySeconds / PrepRules.ReferenceDaySeconds)
	return math.min(seconds, remaining)
end
return PrepRules
