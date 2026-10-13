#!/usr/bin/env node
"use strict";
// Exercise the actual controller against engine-copied GUI + Arms fixtures.
const fs=require("fs"), path=require("path"), fengari=require("fengari");
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=fengari;
const {transformLuau,luaLongString}=require("./lib/luau-transform");
const source=fs.readFileSync(path.join(__dirname,"../code/StarterPlayer/StarterPlayerScripts/Vitriol/Controllers/WatchController.luau"),"utf8");
const code=transformLuau(source,"WatchController");
const fixture=`
local function signal()
 local s={callback=nil}
 function s:Connect(fn) self.callback=fn; return {Disconnect=function() if s.callback==fn then s.callback=nil end end} end
 function s:fire(...) if self.callback then self.callback(...) end end
 return s
end
local function node(class, children)
 local n=children or {}; n.class=class
 function n:IsA(k) return self.class==k or (k=="BasePart" and (self.class=="Part" or self.class=="MeshPart")) end
 function n:WaitForChild(k) assert(self[k], "missing "..k); return self[k] end
 function n:FindFirstChild(k) return self[k] end
 function n:FindFirstChildWhichIsA(k)
  for _,v in pairs(self) do if type(v)=="table" and v.IsA and v:IsA(k) then return v end end
 end
 return n
end
local face=node("TextLabel",{Text=""})
local surface=node("SurfaceGui",{WatchFaceText=face,Enabled=false})
local screen=node("Part",{WatchSurface=surface})
local arm=node("MeshPart",{WristWatch=node("Model",{Screen=screen})})
local animator=node("Animator",{})
local tracks={}
function animator:LoadAnimation(anim)
 assert(anim.AnimationId=="rbxassetid://119603256128899")
 local t={Ended=signal(),IsPlaying=false,Length=1.5,TimePosition=0,stopFade=nil}
 function t:Play(fade) assert(fade>0);self.IsPlaying=true end
 function t:Stop(fade) self.stopFade=fade;self.IsPlaying=false end
 tracks[#tracks+1]=t;return t
end
local viewleft=node("MeshPart",{LocalTransparencyModifier=0.4})
local rig=node("Model",{RightUpperArm=arm, LeftUpperArm=viewleft,
 Humanoid=node("Humanoid",{Animator=animator}),
 CheckWatch=node("Animation",{AnimationId="rbxassetid://119603256128899"}),
 Clothing=node("Shirt",{ShirtTemplate=""})})
viewleft.Parent=rig
function rig:PivotTo(cf) self.lastPivot=cf end
local template=node("LocalScript",{Arms=rig});rig.Parent=template
local gui=node("ScreenGui",{WristViewmodel=node("ViewportFrame",{Visible=true}),
 WatchReadout=node("TextLabel",{Visible=true}),SharedFade=node("Frame",{Visible=false}),Enabled=false})
local playerGui=node("PlayerGui",{});gui.Parent=template
local removing, added, appearance=signal(),signal(),signal()
local right, left=node("Part",{Color="right-skin",LocalTransparencyModifier=0.2}),
 node("Part",{Color="left-skin",LocalTransparencyModifier=0.3})
local character=node("Model",{RightUpperArm=right,LeftUpperArm=left,Shirt=node("Shirt",{ShirtTemplate="shirt://1"})})
right.Parent=character;left.Parent=character
local player=node("Player",{PlayerGui=playerGui,Character=character,CharacterRemoving=removing,
 CharacterAdded=added,CharacterAppearanceLoaded=appearance})
local input={InputBegan=signal(),InputEnded=signal()}
local render=signal(); local run={RenderStepped=render}
local camera={CFrame=setmetatable({}, {__mul=function() return {} end})}
local ws={CurrentCamera=camera}
CFrame={new=function() return {} end}
Enum={KeyCode={T="T"},AnimationPriority={Action="Action"}}
warn=function() end
math.clamp=function(x,a,b) return math.max(a,math.min(x,b)) end
Instance={new=function() error("NO runtime UI, camera, rig or weld allocation") end}
local Controller=assert(load(${luaLongString(4,code)},"WatchController"))()
local watch=Controller.new({Player=player,Workspace=ws,Input=input,RunService=run,
 DayNight={Pacing={DaySeconds=210}},Overlay=gui,Template=template})
assert(gui.Parent==playerGui and rig.Parent==template,"engine-copied assets moved, not cloned")
watch:start()
assert(gui.Enabled and not gui.WristViewmodel.Visible and not gui.WatchReadout.Visible and not surface.Enabled,"only shared fade visible at rest")
assert(rig.Clothing.ShirtTemplate=="shirt://1" and arm.Color=="right-skin", "player shirt + right skin copied")
assert(gui.WristViewmodel.WristCamera==nil,"no client Camera required")
input.InputBegan:fire({KeyCode="T"},true)
assert(#tracks==0,"typing cannot raise")
input.InputBegan:fire({KeyCode="T"},false)
assert(#tracks==1 and rig.Parent==camera and surface.Enabled and watch.active,"tap moves existing rig, starts one shot")
assert(right.LocalTransparencyModifier==1 and left.LocalTransparencyModifier==1
 and viewleft.LocalTransparencyModifier==1,"player's arms and left viewmodel arm locally hidden")
input.InputEnded:fire({KeyCode="T"})
assert(watch.active,"release does not lower one-shot")
input.InputBegan:fire({KeyCode="T"},false)
assert(#tracks==1,"cannot replay concurrently")
watch:receive("Day",0.5)
assert(face.Text=="DAY 01:45" and gui.WatchReadout.Visible==false,"physical screen displays synced time")
watch:receive("Day",0.5,48.8)
assert(face.Text=="DAY 00:49","authoritative remaining budget wins")
watch:receive("Night",0.1)
assert(face.Text=="NIGHT --:--","night has phase and no stale day countdown")
right.LocalTransparencyModifier=0;tracks[1].TimePosition=1.2;render:fire()
assert(right.LocalTransparencyModifier==1,"keeps character arms hidden if default camera resets them")
assert(tracks[1].stopFade==0.35 and rig.lastPivot,"fades smoothly toward idle at animation end; follows camera")
tracks[1].Ended:fire()
assert(not watch.active and rig.Parent==template and not surface.Enabled,"finished pose hides model only after fade")
assert(right.LocalTransparencyModifier==0.2 and left.LocalTransparencyModifier==0.3
 and viewleft.LocalTransparencyModifier==0.4,"all prior local arm visibility restored after check")
character.Shirt.ShirtTemplate="shirt://2";right.Color="new-skin";appearance:fire(character)
assert(rig.Clothing.ShirtTemplate=="shirt://2" and arm.Color=="new-skin","appearance refreshes shirt/skin")
input.InputBegan:fire({KeyCode="T"},false);removing:fire()
assert(rig.Parent==template and not surface.Enabled,"death lowers rig safely")
watch:stop()
assert(not gui.Enabled,"stop hides GUI")
local noRig=Controller.new({Player=player,Workspace=ws,Input=input,RunService=run,
 DayNight={Pacing={DaySeconds=210}},Overlay=gui,Template=node("LocalScript",{})})
assert(noRig and noRig.Fade==gui.SharedFade,"missing optional rig must not break prep fade")
`;
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
const status=lauxlib.luaL_dostring(L,to_luastring(fixture));
if(status!==lua.LUA_OK){console.error("Watch viewmodel test FAILED:",to_jsstring(lua.lua_tostring(L,-1)));process.exitCode=1}
else console.log("Watch viewmodel test: 17 scenarios passed (one-shot, screen, arm hiding, fades, appearance, cleanup, no allocations)");
