--!nonstrict
-- ServerStorage/Tidekeeper/Adapters/PolicyAdapter (ModuleScript)
--
-- Layer L1. doc 13 section 1, decision D3.
--
-- NOTHING IN TIDEKEEPER CURRENTLY DEPENDS ON THIS, AND IT SHIPS ANYWAY.
--
-- Decisions D1 and D2 removed every policy branch the game could have had:
-- no paid random items, no Robux-for-item trading, no free text, no external
-- links. So `ArePaidRandomItemsRestricted` is read and never consulted.
--
-- It ships in iteration 3 regardless, for thirty lines, because:
--   * the plumbing and its Studio Player Emulator test path then already
--     exist the first time a feature does need a branch;
--   * the pre-launch checklist (doc 13 section 6) has a line item that says
--     "PolicyService branches exercised via Studio Player Emulator", and a
--     checklist item with no code behind it is a lie;
--   * a policy call that is added late is added under deadline, in the one
--     part of the codebase where being wrong is a compliance problem.
--
-- The cached shape is deliberately conservative: an unreachable PolicyService
-- yields the MOST restrictive answer, not the most permissive one.

local PolicyAdapter = {}
PolicyAdapter.__index = PolicyAdapter

local function restrictive()
	return {
		paidRandomItemsRestricted = true,
		paidItemTradingAllowed = false,
		subjectToChinaPolicies = true,
		allowedExternalLinkReferences = {},
		loaded = false,
	}
end

function PolicyAdapter.new(options)
	local opts = options or {}
	local self = setmetatable({}, PolicyAdapter)
	self.service = opts.service
	if self.service == nil then
		local ok, service = pcall(function()
			return game:GetService("PolicyService")
		end)
		if ok then
			self.service = service
		end
	end
	self.logger = opts.logger
	self.cache = {}
	self.stats = { loaded = 0, failed = 0 }
	return self
end

function PolicyAdapter:log(message)
	if self.logger ~= nil then
		self.logger("PolicyAdapter", message)
	end
end

-- Called from PlayerAdded BEFORE anything monetised (doc 01 section 7).
-- Returns the cached record; it is never nil.
function PolicyAdapter:load(player)
	local userId = player.UserId
	local cached = self.cache[userId]
	if cached ~= nil then
		return cached
	end
	local record = restrictive()
	if self.service == nil then
		self.stats.failed = self.stats.failed + 1
		self.cache[userId] = record
		return record
	end
	local ok, info = pcall(function()
		return self.service:GetPolicyInfoForPlayerAsync(player)
	end)
	if not ok or type(info) ~= "table" then
		self.stats.failed = self.stats.failed + 1
		self:log("policy load failed for " .. tostring(userId) .. ", assuming the most restrictive answer")
		self.cache[userId] = record
		return record
	end
	record.paidRandomItemsRestricted = info.ArePaidRandomItemsRestricted == true
	record.paidItemTradingAllowed = info.IsPaidItemTradingAllowed == true
	record.subjectToChinaPolicies = info.IsSubjectToChinaPolicies == true
	record.allowedExternalLinkReferences = info.AllowedExternalLinkReferences or {}
	record.loaded = true
	self.stats.loaded = self.stats.loaded + 1
	self.cache[userId] = record
	return record
end

function PolicyAdapter:get(userId)
	return self.cache[userId] or restrictive()
end

function PolicyAdapter:forget(userId)
	self.cache[userId] = nil
end

-- The two questions the game would ask if D1 and D2 were ever reopened.
-- They exist so that reopening those decisions is a code change here and
-- nowhere else.
function PolicyAdapter:mayOfferPaidRandomItems(userId)
	return self:get(userId).paidRandomItemsRestricted ~= true
end

function PolicyAdapter:mayTradePaidItems(userId)
	return self:get(userId).paidItemTradingAllowed == true
end

return PolicyAdapter
