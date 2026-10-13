#!/usr/bin/env node
"use strict";
// The real controller, an authored Frame, fake server-time and RenderStepped.
// This is timing/state proof, not a Roblox network or visual Play verdict.
const fs = require("fs");
const path = require("path");
const fengari = require("fengari");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const { transformLuau, luaLongString } = require("./lib/luau-transform");
const source = fs.readFileSync(path.join(__dirname, "../code/StarterPlayer/StarterPlayerScripts/Vitriol/Controllers/PrepFadeController.luau"), "utf8");
const code = transformLuau(source, "PrepFadeController");
const fixture = `
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
math.clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
Instance={new=function() error("runtime Instance creation forbidden") end}
local callback=nil
local connects,disconnects=0,0
local run={RenderStepped={Connect=function(_,fn)
  connects=connects+1; callback=fn
  return {Disconnect=function() disconnects=disconnects+1; callback=nil end}
end}}
local function step() if callback then callback() end end
local now=10
local function near(a,b) return math.abs(a-b)<0.001 end
local function frame() return {Visible=true,BackgroundTransparency=0,IsA=function(_,k) return k=="Frame" end} end
local Controller=assert(load(${luaLongString(4,code)},"PrepFadeController"))()
check(Controller.new({Frame=nil,RunService=run,Clock=function() return now end})==nil,
  "missing authored frame never gets constructed")
local f=frame()
local c=Controller.new({Frame=f,RunService=run,Clock=function() return now end})
check(f.BackgroundTransparency==1 and not f.Visible,"authored Frame initially hidden")
c:receive(nil); c:receive({serial=1,stage="blackout",startedAt=0,seconds=99})
check(c.serial==0 and connects==0,"invalid/stale-or-huge network data fails closed")
c:receive({serial=1,stage="vote",startedAt=10,seconds=3})
check(c.stage=="vote" and not f.Visible and connects==0,"vote does not cover the screen")
c:receive({serial=1,stage="blackout",startedAt=10,seconds=.35})
check(c.stage=="blackout" and f.Visible and near(f.BackgroundTransparency,1) and connects==1,
  "blackout begins transparent on preauthored Frame")
now=10.175;step()
check(near(f.BackgroundTransparency,.5),"fade-in tracks authoritative timestamp, not packet count")
c:receive({serial=1,stage="blackout",startedAt=10.175,seconds=.35})
check(near(f.BackgroundTransparency,.5) and connects==1,"repeated snapshot cannot restart fade")
c:receive({serial=1,stage="vote",startedAt=10.175,seconds=3})
check(c.stage=="blackout","stale lower stage cannot un-black")
now=10.36;step()
check(near(f.BackgroundTransparency,0) and f.Visible and callback==nil and disconnects==1,
  "blackout holds opaque without a permanent per-frame listener")
c:receive({serial=1,stage="reveal",startedAt=10.35,seconds=.4})
now=10.55;step()
check(near(f.BackgroundTransparency,.5),"reveal fades back out from black")
now=10.76;step()
check(not f.Visible and near(f.BackgroundTransparency,1) and callback==nil,
  "reveal hides frame and unbinds RenderStepped")
c:receive({serial=1,stage="clear",startedAt=10.75,seconds=0})
check(not f.Visible,"clear resets already completed fade idempotently")
now=20
c:receive({serial=2,stage="vote",startedAt=20,seconds=3})
c:receive({serial=2,stage="blackout",startedAt=20,seconds=.35})
now=20.175;step()
c:receive({serial=2,stage="cancel",startedAt=now,seconds=.4})
check(near(f.BackgroundTransparency,.5),"cancel starts at current opacity, with no black flash")
now=20.6;step()
check(not f.Visible and callback==nil,"cancel cleans up a partially completed fade")
local late=frame()
now=42
local newcomer=Controller.new({Frame=late,RunService=run,Clock=function() return now end})
newcomer:receive({serial=5,stage="blackout",startedAt=41,seconds=.35})
check(late.Visible and near(late.BackgroundTransparency,0) and callback==nil,
  "late joiner who missed fade-in sees current blackout immediately")
newcomer:receive({serial=5,stage="reveal",startedAt=41.7,seconds=.4})
check(near(late.BackgroundTransparency,.75),"late joiner catches up to remaining reveal")
newcomer:receive({serial=4,stage="blackout",startedAt=42,seconds=.35})
check(newcomer.serial==5 and near(late.BackgroundTransparency,.75),"out-of-order older serial ignored")
newcomer:stop();c:stop()
check(not late.Visible and not f.Visible and callback==nil,"stop unbinds and restores hidden authored frames")
print("Prep fade controller: "..checks.." scenarios passed")
`;
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const status = lauxlib.luaL_dostring(L, to_luastring(fixture));
if (status !== lua.LUA_OK) {
  console.error("Prep fade controller FAILED:", to_jsstring(lua.lua_tostring(L,-1)));
  process.exitCode = 1;
} else console.log("Prep fade controller assertions passed");
