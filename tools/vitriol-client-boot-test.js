#!/usr/bin/env node
"use strict";
// Execute the actual ClientMain source in a tiny fake client DataModel. The
// replicated root does not exist at script start: only WaitForChild delivers it.
// This catches eager ReplicatedStorage.Vitriol indexing and missing time listeners.
const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const { transformLuau } = require("./lib/luau-transform");
const source = fs.readFileSync(path.join(__dirname, "../code/StarterPlayer/StarterPlayerScripts/Vitriol/ClientMain.luau"), "utf8");
const client = transformLuau(source, "ClientMain");
const fixture = `
local bound, received, started, waitedForRoot, watchStarted = 0, nil, 0, 0, 0
local watchPhase, watchProgress, watchBudget, watchReceives = nil, nil, nil, 0
local fadeStage, fadeReceives, fadeBound = nil, 0, 0
local remote = { OnClientEvent = { Connect = function(_, fn) bound = bound + 1; remoteCallback = fn end } }
local comms = { WaitForChild = function(_, name)
  assert(name == "RE_TimeSync"); return remote
end }
local config = { WaitForChild = function(_, name) assert(name == "DayNightConfig"); return { kind = "config" } end }
local sharedModules = { WaitForChild = function(_, name) assert(name == "Remotes"); return { FolderName = "Comms", await = function(name)
  assert(name == "RE_CreatureEvent"); return { kind = "creature" }
end } end }
local root = { WaitForChild = function(_, name)
  if name == "Comms" then return comms end
  if name == "Config" then return config end
  if name == "Shared" then return sharedModules end
  error("unexpected root child " .. name)
end }
local replicated = setmetatable({ WaitForChild = function(_, name)
  assert(name == "Vitriol"); waitedForRoot = waitedForRoot + 1; return root
end }, { __index = function(_, name) error("eager replicated root access: " .. name) end })
local services = { Players = { LocalPlayer = {} }, ReplicatedStorage = replicated,
  RunService = {}, Workspace = {GetServerTimeNow=function() return 100 end}, Lighting = {}, UserInputService = {} }
game = { GetService = function(_, name) assert(services[name], name); return services[name] end }
local controllers = { VictimCamera = { kind = "camera" }, LightingDriver = { kind = "lighting" }, WatchController = { kind = "watch" }, PrepFadeController = { kind = "fade" } }
local authoredFade = {kind="frame"}
controllers.WaitForChild = function(self, name) assert(self[name], name); return self[name] end
local authoredOverlay = { kind = "overlay" }
script = { Parent = { WaitForChild = function(_, name) assert(name == "Controllers"); return controllers end },
  FindFirstChild = function(_, name) assert(name == "VitriolWatchOverlay"); return authoredOverlay end }
function VitriolRequire(name) return require(controllers[name]) end
function require(node)
  if node.kind == "camera" then return { new = function() return { bind = function(_, ev) assert(ev.kind == "creature") end } end } end
  if node.kind == "lighting" then return { new = function() return {
    receive = function(_, minutes) received = minutes end,
    start = function() started = started + 1; remoteCallback(600, "Dawn", 0.25, 0, 0, "Clear", 555, 208, {serial=3,stage="blackout",seconds=.35,startedAt=100}) end,
  } end } end
  if node.kind == "watch" then return { new = function(s) assert(s.Overlay == authoredOverlay); return {
    Fade = authoredFade,
    start = function() watchStarted = watchStarted + 1 end,
    receive = function(_, phase, progress, budget) watchPhase, watchProgress, watchBudget = phase, progress, budget; watchReceives = watchReceives + 1 end,
  } end } end
  if node.kind == "fade" then return { new = function(s) assert(s.Frame == authoredFade and s.Clock() == 100); fadeBound = fadeBound + 1; return {
    receive = function(_, state) fadeStage = state.stage; fadeReceives = fadeReceives + 1 end,
  } end } end
  if node.kind == "config" then return {} end
  if node.FolderName == "Comms" then return node end
  error("unexpected require")
end
local printLog = {}
print = function(msg) printLog[#printLog + 1] = msg end
`;
const check = `
assert(waitedForRoot == 1, "did not await delayed replicated root")
assert(bound == 1, "RE_TimeSync not subscribed exactly once")
assert(started == 1, "LightingDriver did not start")
assert(watchStarted == 1, "WatchController did not start")
assert(watchPhase == "Dawn" and watchProgress == 0.25 and watchReceives == 1,
  "watch did not replay early server sync after it bound")
assert(fadeBound == 1 and fadeStage == "blackout" and fadeReceives == 1,
  "client did not replay an early blackout into the preauthored fade controller")
assert(remoteCallback ~= nil, "no sync callback")
remoteCallback(713.5, "Day", 0.5, 0, 0, "Clear", 555, 48.8, {serial=3,stage="reveal",seconds=.4,startedAt=101})
assert(received == 713.5, "numeric clock did not reach LightingDriver")
assert(watchPhase == "Day" and watchProgress == 0.5 and watchBudget == 48.8 and watchReceives == 2,
  "later server sync did not deliver Day budget to raised watch")
assert(fadeStage == "reveal" and fadeReceives == 2,
  "later server fade packet was not delivered through RE_TimeSync")
assert(printLog[1] == "[vitriol.client] ClientMain started", "missing startup diagnostic")
assert(printLog[2] == "[vitriol.client] RE_TimeSync listener bound", "missing bind diagnostic")
`;
const bundle = fixture + "\n" + client + "\n" + check;
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, to_luastring(bundle));
if (status !== lua.LUA_OK) {
  console.error("Client delayed-replication regression FAILED:", to_jsstring(lua.lua_tostring(L, -1)));
  process.exitCode = 1;
} else {
  console.log("Client delayed-replication regression: 1 passed, 0 failed (root late; time listener and numeric clock delivered)");
}
