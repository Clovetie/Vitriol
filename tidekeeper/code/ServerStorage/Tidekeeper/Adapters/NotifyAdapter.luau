--!nonstrict
-- ServerStorage/Tidekeeper/Adapters/NotifyAdapter (ModuleScript)
--
-- Layer L1. The only module that sends a notification.
--
-- WRITTEN AGAINST WHAT SHIPPED, NOT WHAT WAS ANNOUNCED
-- ----------------------------------------------------
-- Verified 2026-10-01 (doc 10 section 6.1): the turn-based notification
-- system Roblox announced at RDC 2026 is due in Studio Beta this month and in
-- full release by the end of the year. IT IS NOT OUT. `ExperienceNotification-
-- Service` still exposes exactly `CanPromptOptInAsync`, `PromptOptIn` and
-- `OptInPromptClosed`, and the only send path is the Creator Store Open Cloud
-- Luau package:
--
--   local OCUserNotification = require(ServerScriptService.OpenCloud.V2.UserNotification)
--   OCUserNotification.createUserNotification(userId, {
--     payload = { messageId = <dashboard asset id>, type = "MOMENT",
--                 parameters = { ... }, joinExperience = { launchData = ... } }
--   })
--
-- Consequences baked into this file:
--
--   * The package may simply not be installed. `require` on a missing
--     Instance throws, so it is resolved with FindFirstChild and the adapter
--     reports itself DISABLED rather than erroring. A disabled notifier is
--     the expected state in Studio, in the harness, and on day one.
--   * The body is not free text. It is a messageId naming a <= 99-character
--     string authored in the Creator Dashboard, plus named parameters. That
--     is a perfect fit for a game that forbids free text everywhere else
--     (doc 13 section 2) -- and it means NotifyConfig, not this file, decides
--     what a notification can say.
--   * One per user per day per experience, statically throttled, and
--     DELIVERY IS NOT GUARANTEED: reach is weighted by engagement. So nothing
--     may depend on a send succeeding.
--   * Roblox forbids gating gameplay on notifications. Nothing here is
--     load-bearing and `send` never yields the caller into a failure path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NotifyConfig = require(Tidekeeper.Config.NotifyConfig)

local NotifyAdapter = {}
NotifyAdapter.__index = NotifyAdapter

NotifyAdapter.STATUS_OK = "ok"
NotifyAdapter.STATUS_DISABLED = "disabled"
NotifyAdapter.STATUS_THROTTLED = "throttled"
NotifyAdapter.STATUS_REJECTED = "rejected"
NotifyAdapter.STATUS_ERROR = "error"

local function newStats()
	return { attempted = 0, sent = 0, throttled = 0, rejected = 0, errored = 0, skippedDisabled = 0 }
end

function NotifyAdapter.new(options)
	local opts = options or {}
	local self = setmetatable({}, NotifyAdapter)
	self.logger = opts.logger
	self.stats = newStats()
	-- An explicit override exists so the harness can exercise BOTH the
	-- disabled path (the default, and the interesting one) and a successful
	-- send without pretending Open Cloud is reachable.
	self.sender = opts.sender
	self.reason = nil
	-- Eligibility: the experience needs at least MIN_VISITS_REQUIRED visits
	-- since launch before Roblox will deliver anything at all. On a brand
	-- new place that is simply false, and pretending otherwise would mean
	-- burning a request per logout to be told so.
	self.experienceVisits = opts.experienceVisits or 0
	if self.sender == nil then
		self.sender, self.reason = NotifyAdapter._resolvePackage(opts.container)
	end
	self.enabled = self.sender ~= nil
	if not self.enabled then
		self:log("notifications disabled: " .. tostring(self.reason))
	end
	return self
end

function NotifyAdapter:log(message)
	if self.logger ~= nil then
		self.logger("NotifyAdapter", message)
	end
end

-- Resolve `ServerScriptService.OpenCloud.V2.UserNotification` defensively.
-- `require` on a nil Instance throws, and an uninstalled Creator Store
-- package is the normal state of a fresh place.
function NotifyAdapter._resolvePackage(container)
	local root = container
	if root == nil then
		local ok, service = pcall(function()
			return game:GetService("ServerScriptService")
		end)
		if not ok then
			return nil, "ServerScriptService unavailable"
		end
		root = service
	end
	local openCloud = root:FindFirstChild("OpenCloud")
	if openCloud == nil then
		return nil, "the OpenCloud package is not installed"
	end
	local v2 = openCloud:FindFirstChild("V2")
	if v2 == nil then
		return nil, "OpenCloud.V2 is missing"
	end
	local module = v2:FindFirstChild("UserNotification")
	if module == nil then
		return nil, "OpenCloud.V2.UserNotification is missing"
	end
	local ok, loaded = pcall(function()
		return require(module)
	end)
	if not ok or type(loaded) ~= "table" or type(loaded.createUserNotification) ~= "function" then
		return nil, "OpenCloud.V2.UserNotification did not load"
	end
	return function(userId, payload)
		return loaded.createUserNotification(userId, payload)
	end, nil
end

function NotifyAdapter:messageIdFor(kind)
	local id = NotifyConfig.MESSAGE_IDS[kind]
	if id == nil or id == NotifyConfig.PLACEHOLDER_ID then
		return nil
	end
	return id
end

-- Returns (status, detail). NEVER errors, never retries: a notification that
-- did not go out is a non-event, and a retry storm at logout is not.
function NotifyAdapter:send(userId, kind, parameters, launchData)
	self.stats.attempted = self.stats.attempted + 1
	if not self.enabled then
		self.stats.skippedDisabled = self.stats.skippedDisabled + 1
		return NotifyAdapter.STATUS_DISABLED, self.reason
	end
	if self.experienceVisits < NotifyConfig.MIN_VISITS_REQUIRED then
		self.stats.skippedDisabled = self.stats.skippedDisabled + 1
		return NotifyAdapter.STATUS_DISABLED, "the experience has fewer than " .. tostring(NotifyConfig.MIN_VISITS_REQUIRED) .. " visits"
	end
	local messageId = self:messageIdFor(kind)
	if messageId == nil then
		self.stats.skippedDisabled = self.stats.skippedDisabled + 1
		return NotifyAdapter.STATUS_DISABLED, "no dashboard string is authored for kind " .. tostring(kind)
	end

	local payloadParameters = {}
	local names = NotifyConfig.PARAMETERS[kind]
	if names ~= nil and parameters ~= nil then
		for i = 1, #names do
			local key = names[i]
			local value = parameters[key]
			if value ~= nil then
				if type(value) == "number" then
					payloadParameters[key] = { int64Value = value }
				else
					payloadParameters[key] = { stringValue = tostring(value) }
				end
			end
		end
	end

	local request = {
		payload = {
			messageId = messageId,
			type = "MOMENT",
			parameters = payloadParameters,
		},
	}
	if launchData ~= nil then
		request.payload.joinExperience = { launchData = tostring(launchData) }
	end
	request.payload.analyticsData = { category = NotifyConfig.KIND_NAMES[kind] or "UNKNOWN" }

	-- SEND_ATTEMPTS is 1 and should stay 1. A notification that did not go
	-- out is a non-event; a retry storm at logout, while BindToClose is
	-- trying to save everybody, is not. The loop exists so that the number
	-- is a config value somebody can reason about rather than an absence.
	local ok, result
	for _ = 1, NotifyConfig.SEND_ATTEMPTS do
		ok, result = pcall(function()
			return self.sender(userId, request)
		end)
		if ok then
			break
		end
	end
	if not ok then
		self.stats.errored = self.stats.errored + 1
		self:log("send errored: " .. tostring(result))
		return NotifyAdapter.STATUS_ERROR, tostring(result)
	end
	if type(result) ~= "table" then
		self.stats.errored = self.stats.errored + 1
		return NotifyAdapter.STATUS_ERROR, "sender returned " .. type(result)
	end
	if result.statusCode == 200 then
		self.stats.sent = self.stats.sent + 1
		return NotifyAdapter.STATUS_OK, nil
	end
	if result.statusCode == 429 then
		self.stats.throttled = self.stats.throttled + 1
		return NotifyAdapter.STATUS_THROTTLED, "daily cap reached"
	end
	self.stats.rejected = self.stats.rejected + 1
	local detail = "status " .. tostring(result.statusCode)
	if type(result.error) == "table" and result.error.message ~= nil then
		detail = detail .. ": " .. tostring(result.error.message)
	end
	return NotifyAdapter.STATUS_REJECTED, detail
end

function NotifyAdapter:resetStats()
	self.stats = newStats()
end

return NotifyAdapter
