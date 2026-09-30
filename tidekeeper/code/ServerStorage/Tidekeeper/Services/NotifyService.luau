--!nonstrict
-- ServerStorage/Tidekeeper/Services/NotifyService (ModuleScript)
--
-- Layer L3. Decides WHETHER and WHAT to send. `NotifyAdapter` decides HOW.
-- The split exists because the how is going to change -- the turn-based
-- notification API announced at RDC 2026 is due in Studio Beta this month
-- (doc 10 section 6.1) -- and the whether should not change with it.
--
-- THE RULES THIS SERVICE ENFORCES, AND WHY EACH ONE IS NOT NEGOTIABLE
-- -------------------------------------------------------------------
-- 1. ONE PER USER PER DAY. Roblox enforces this server-side and reports the
--    throttle back, but a game that relies on the platform to stop it from
--    spamming is a game that spams the moment the platform's rule changes.
--    We track it ourselves and we send fewer than we are allowed.
--
-- 2. NOTHING MAY GATE GAMEPLAY. Platform policy, and also just correct:
--    delivery is explicitly NOT GUARANTEED (reach is scaled by engagement),
--    so a design that needs the notification to arrive is a design that
--    breaks for the players it reaches least. Every notification here is a
--    report on something that ALREADY HAPPENED and is waiting whether or not
--    you are told. The Ledger is the truth; the notification is a courtesy.
--
-- 3. IT MUST BE PERSONAL AND ACTIONABLE. "Your post has 8 letters waiting"
--    is a fact about your post. "Come back and play!" is an advertisement,
--    and Roblox rejects it. Every kind in NotifyConfig names a specific
--    thing that a specific person did.
--
-- 4. NO FALSE URGENCY. There is no "your goods expire in 1 hour!". The tide
--    is a real clock and it does not need a countdown to be interesting.
--
-- 5. ELIGIBILITY IS THE PLATFORM'S CALL. 13+, opted in, experience has 100+
--    visits, not under moderation. We check what we can and treat a refusal
--    as normal, not as an error.
--
-- The single most likely outcome of a call to this service, for the entire
-- life of the project, is "disabled". That is fine. Everything downstream is
-- written so that is the boring path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NotifyConfig = require(Tidekeeper.Config.NotifyConfig)
local Tide = require(Tidekeeper.Lib.Tide)

local NotifyService = {}
NotifyService.__index = NotifyService

local function newStats()
	return {
		considered = 0,
		suppressedDaily = 0,
		suppressedPriority = 0,
		suppressedEmpty = 0,
		suppressedLead = 0,
		dispatched = 0,
	}
end

function NotifyService.new(options)
	local opts = options or {}
	local self = setmetatable({}, NotifyService)
	self.adapter = opts.adapter
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.stats = newStats()
	-- userId -> { day = <day number>, kind = <kind sent that day> }
	self.lastSent = {}
	-- userId -> the best candidate accumulated this session
	self.candidates = {}
	return self
end

function NotifyService:log(message)
	if self.logger ~= nil then
		self.logger("NotifyService", message)
	end
end

function NotifyService:dayNumber(now)
	return math.floor(now / NotifyConfig.DAY_SECONDS)
end

-- Offer a candidate. Only the HIGHEST-PRIORITY candidate per user survives,
-- because the daily budget is one and spending it on "someone browsed and
-- left" when "your traveller came home with a full hold" is also true would
-- be the wrong call.
-- `at` is when the thing being reported happens, in UTC seconds. It is
-- optional; when given, the candidate is only kept if it falls inside the
-- lead-time window. Too soon and the player cannot act on it; too far out
-- and we are guessing at their plans, which is exactly the "false urgency /
-- manufactured FOMO" pattern the platform's content rules forbid.
function NotifyService:consider(userId, kind, parameters, launchData, at)
	self.stats.considered = self.stats.considered + 1
	local priority = NotifyConfig.PRIORITY[kind] or 0
	if priority <= 0 then
		return false
	end
	if at ~= nil then
		local lead = at - self.clock()
		if lead < NotifyConfig.MIN_LEAD_SECONDS or lead > NotifyConfig.MAX_LEAD_SECONDS then
			self.stats.suppressedLead = self.stats.suppressedLead + 1
			return false
		end
	end
	local existing = self.candidates[userId]
	if existing ~= nil and (NotifyConfig.PRIORITY[existing.kind] or 0) >= priority then
		self.stats.suppressedPriority = self.stats.suppressedPriority + 1
		return false
	end
	self.candidates[userId] = {
		kind = kind,
		parameters = parameters or {},
		launchData = launchData,
	}
	return true
end

-- Convenience: the inbox notification, the one that actually earns its place.
-- Below INBOX_THRESHOLD there is nothing worth interrupting anyone for.
function NotifyService:considerInbox(userId, letterCount, epoch)
	if letterCount < NotifyConfig.INBOX_THRESHOLD then
		self.stats.suppressedEmpty = self.stats.suppressedEmpty + 1
		return false
	end
	return self:consider(userId, NotifyConfig.KIND_INBOX_FULL, { count = letterCount }, "inbox:" .. tostring(epoch))
end

-- Called at logout, once, after the post is saved. This is the only moment
-- we know both what happened and that the player is not currently looking at
-- it -- and a notification about something you are already looking at is the
-- definition of spam.
function NotifyService:flush(userId)
	local candidate = self.candidates[userId]
	self.candidates[userId] = nil
	if candidate == nil then
		return false, "nothing to say"
	end
	local now = self.clock()
	local day = self:dayNumber(now)
	local last = self.lastSent[userId]
	if last ~= nil and last.day == day and last.count >= NotifyConfig.MAX_PER_USER_PER_DAY then
		self.stats.suppressedDaily = self.stats.suppressedDaily + 1
		return false, "already sent today"
	end
	if self.adapter == nil then
		return false, "no adapter"
	end
	local status, detail = self.adapter:send(userId, candidate.kind, candidate.parameters, candidate.launchData)
	if status == "ok" then
		self:noteSent(userId, day, candidate.kind)
		self.stats.dispatched = self.stats.dispatched + 1
		return true, status
	end
	if status == "throttled" then
		-- The platform's own daily cap. Record it as spent so we do not spend
		-- a request finding out again.
		self:noteSent(userId, day, candidate.kind)
	end
	return false, status .. (detail and (": " .. detail) or "")
end

function NotifyService:noteSent(userId, day, kind)
	local last = self.lastSent[userId]
	if last == nil or last.day ~= day then
		self.lastSent[userId] = { day = day, kind = kind, count = 1 }
		return
	end
	last.count = last.count + 1
	last.kind = kind
end

-- Client-side opt-in prompting is a CLIENT concern
-- (`ExperienceNotificationService` is client-only), so this service only
-- decides whether the moment is right. doc 13 section 4: never on the join
-- frame, never during a resolve, and only after the player has seen the
-- Ledger pay off at least once.
function NotifyService:shouldPromptOptIn(sessionSeconds, ledgerEntriesSeen, alreadyPrompted)
	if alreadyPrompted then
		return false
	end
	if ledgerEntriesSeen < 3 then
		return false
	end
	return sessionSeconds >= 300
end

-- Epoch-aligned launch data, so the client can open straight to the right
-- page of the Ledger via `Player:GetJoinData()`.
function NotifyService:launchDataFor(epoch)
	return "e" .. tostring(Tide.epoch(self.clock()) - epoch)
end

function NotifyService:forget(userId)
	self.candidates[userId] = nil
end

function NotifyService:resetStats()
	self.stats = newStats()
end

return NotifyService
