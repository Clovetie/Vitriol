--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/Remotes (ModuleScript)
--
-- THE ONLY PLACE IN THE GAME WHERE A REMOTE IS CREATED (doc 01 section 4).
--
-- Layer: Shared. This is the single exception to "Shared is pure", and it is
-- deliberate: the alternative is remotes created in whichever service happens
-- to need one first, which is how a project ends up with eleven of them and
-- no idea which are validated. The exception is visible rather than quiet --
-- every platform line below carries a `determinism-scan: allow` comment, and
-- the scan prints every allowance in its report.
--
-- What the remote surface is allowed to be is `Shared/NetContract`, which is
-- pure and therefore testable without any of this.

local NetContract = require(script.Parent.NetContract)

local Remotes = {}

local FOLDER_NAME = "TidekeeperRemotes"

local cache = nil

local function classOf(direction)
	if direction == NetContract.DIR_S2C then
		return "RemoteEvent"
	end
	return "RemoteFunction"
end

-- Server-side. Creates the folder and the seven remotes, exactly once, and
-- returns a name -> Instance map. Calling it twice returns the same table.
function Remotes.build()
	if cache ~= nil then
		return cache
	end
	-- determinism-scan: allow services Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
	local replicated = game:GetService("ReplicatedStorage")
	local folder = replicated:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		-- determinism-scan: allow services Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = replicated
	end
	local map = {}
	for i = 1, #NetContract.REMOTES do
		local row = NetContract.REMOTES[i]
		local name = row[1]
		local existing = folder:FindFirstChild(name)
		if existing == nil then
			-- determinism-scan: allow services Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
			existing = Instance.new(classOf(row[2]))
			existing.Name = name
			existing.Parent = folder
		end
		map[name] = existing
	end
	cache = map
	return map
end

-- Client-side. Never creates anything; waits for what the server made.
function Remotes.await(timeout)
	if cache ~= nil then
		return cache
	end
	-- determinism-scan: allow services Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
	local replicated = game:GetService("ReplicatedStorage")
	local folder = replicated:WaitForChild(FOLDER_NAME, timeout or 30)
	if folder == nil then
		return nil, "remote folder never appeared"
	end
	local map = {}
	for i = 1, #NetContract.REMOTES do
		local name = NetContract.REMOTES[i][1]
		local remote = folder:WaitForChild(name, timeout or 30)
		if remote == nil then
			return nil, "remote " .. name .. " never appeared"
		end
		map[name] = remote
	end
	cache = map
	return map
end

-- Testing seam. The harness builds a fresh DataModel per scenario, so the
-- module-level cache has to be droppable; nothing in the game calls this.
function Remotes._reset()
	cache = nil
end

Remotes.FOLDER_NAME = FOLDER_NAME

return Remotes
