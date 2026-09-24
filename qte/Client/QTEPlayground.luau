--!strict
-- QTEPlayground.luau
-- Location: StarterPlayer > StarterPlayerScripts > QTEPlayground (LocalScript)
-- Purpose:  The smallest way to SEE the system: press a key, get a QTE. Nothing here
--           is needed by the package - it exists so the overlay can be looked at in
--           a place with no game attached to it yet, and so a new QTE can be tried
--           without wiring a server.
--
--           F8  random QTE (what the pool would serve this device)
--           F9  a three-step chain: Reflex -> Motor -> Memory
--           F10 cancel whatever is running
--           F11 print the grade table of the last run and the session stats
--
--           The result arrives on struggle.resultSignal; a real game would send it
--           to the server and let the server decide what it means (README.md §10).
--
-- Install: REPLACE QTEStruggleClient with this file, or keep both - this one only
-- adds keybinds, it does not start anything by itself.
--
-- Requires: ReplicatedStorage.QTE.Client.QTEStruggle
-- Used by:  nothing (developer tool)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local package = ReplicatedStorage:WaitForChild("QTE")
local QTEStruggle = require(package.Client.QTEStruggle)

local struggle = QTEStruggle.new({
	Players = Players,
	RunService = game:GetService("RunService"),
	Workspace = game:GetService("Workspace"),
	Player = Players.LocalPlayer,
	seed = os.time() % 100000,
	freeze = false,
	preset = "Normal",
})

-- The three-step chain F9 runs. These are catalogue ids; GetQTEList() prints every
-- one this device can be asked for.
local CHAIN = { "Spam", "StepTiming", "FlashDigit" }

local runs = 0
local wins = 0

struggle.resultSignal:connect(function(result: any)
	runs += 1
	if result.grade ~= "fail" and result.cancelled ~= true then
		wins += 1
	end
	print(string.format(
		"[qte] %s -> %s (%s) score %.2f, weight %.2f, %.2fs, %d miss(es)%s",
		tostring(result.id),
		tostring(result.grade),
		tostring(result.reason),
		result.score or 0,
		result.escapeWeight or 0,
		result.elapsed or 0,
		result.misses or 0,
		result.cancelled and " [cancelled]" or ""
	))
end)

UserInputService.InputBegan:Connect(function(key: any, processed: boolean)
	if processed then
		return
	end
	if key.KeyCode == Enum.KeyCode.F8 then
		struggle:StartRandomQTE()
	elseif key.KeyCode == Enum.KeyCode.F9 then
		struggle:StartChain(CHAIN)
	elseif key.KeyCode == Enum.KeyCode.F10 then
		struggle:cancel("playground")
	elseif key.KeyCode == Enum.KeyCode.F11 then
		local stats = struggle:GetStats()
		print(string.format("[qte] %d run(s), %d escaped, preset %s", runs, wins, tostring(stats.preset)))
		local list = struggle:GetQTEList()
		local ids = {}
		for i = 1, #list do
			ids[#ids + 1] = list[i].id
		end
		print("[qte] this device can be asked for: " .. table.concat(ids, ", "))
	end
end)
