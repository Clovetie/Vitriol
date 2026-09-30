--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/NotifyConfig (ModuleScript)
--
-- Notification kinds, priorities and dashboard message ids.
--
-- Layer: Config (data only -- no requires, no services, no functions).
--
-- WHAT SHIPPED, AS OF 2026-10-01 (doc 10 section 6.1)
-- --------------------------------------------------
-- The turn-based notification system announced at RDC 2026 is NOT out yet. It
-- is due in Studio Beta this month and in full release by the end of the year.
-- Until it lands, the only send path is the Creator Store Open Cloud package:
--
--   OpenCloud.V2.UserNotification.createUserNotification(userId, {
--     payload = { messageId = <asset id>, type = "MOMENT", parameters = {...} }
--   })
--
-- `messageId` names a notification string AUTHORED IN THE CREATOR DASHBOARD,
-- at most 99 characters, with named parameters substituted at send time. There
-- is no free-text notification body, which suits a game that already forbids
-- free text everywhere else (doc 13 section 2).
--
-- The MESSAGE_IDS below are therefore placeholders: the real asset ids can
-- only be minted once the experience exists. `NotifyAdapter` treats a
-- placeholder id as "not configured" and reports the notifier disabled rather
-- than sending garbage. The game is fully playable in that state -- and the
-- session harness runs its whole 30-day lifetime that way on purpose.

return {
	-- Kind ids. Wire-stable: they are persisted in the pending-notification
	-- slot of the post blob. Never renumber.
	KIND_DEEPWATER = 1,
	KIND_SPRING_TIDE = 2,
	KIND_NAMED_RETURN = 3,
	KIND_INBOX_FULL = 4,

	-- Priority order, best first. doc 03 section 10.
	PRIORITY = { 1, 2, 3, 4 },

	KIND_NAMES = { "DEEPWATER", "SPRING_TIDE", "NAMED_RETURN", "INBOX_FULL" },

	-- Dashboard asset ids, one per kind, indexed by kind id. A value equal to
	-- PLACEHOLDER_ID means "no string has been authored yet".
	PLACEHOLDER_ID = "00000000-0000-0000-0000-000000000000",
	MESSAGE_IDS = {
		"00000000-0000-0000-0000-000000000000",
		"00000000-0000-0000-0000-000000000000",
		"00000000-0000-0000-0000-000000000000",
		"00000000-0000-0000-0000-000000000000",
	},

	-- Parameter names per kind, as arrays of strings (doc 04 D8: arrays of
	-- arrays, never named sub-keys, so find-dead-config can see the top key).
	PARAMETERS = {
		{ "atTime" },
		{ "atTime" },
		{ "who" },
		{ "count" },
	},

	-- The platform throttle is one notification per user per day per
	-- experience, and delivery is not guaranteed. We enforce the same cap
	-- locally: a rejected send still costs a request, and the cap is also the
	-- design intent (doc 03 section 10).
	MAX_PER_USER_PER_DAY = 1,
	DAY_SECONDS = 86400,

	-- Do not schedule anything further out than this; the tide is exact but
	-- the player's intentions are not.
	MAX_LEAD_SECONDS = 172800,
	-- Nor anything so close that the player cannot act on it.
	MIN_LEAD_SECONDS = 600,

	-- INBOX_FULL fires at this many unread receipts (doc 03 section 10).
	INBOX_THRESHOLD = 8,

	-- Requests are cheap but not free, and the adapter must never stall a
	-- logout. One attempt, no retry: a missed notification is a non-event.
	SEND_ATTEMPTS = 1,

	-- Recipients must be 13+ and opted in. We cannot know that server-side
	-- without spending the day's notification, so the adapter simply attempts
	-- the send and records the rejection.
	MIN_VISITS_REQUIRED = 100,
}
