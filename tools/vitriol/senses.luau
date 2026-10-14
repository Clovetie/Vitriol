-- Eye-less directional sight + close thermal, not live-map omniscience.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local p=R.Players:addPlayer("HiddenSurvivor",50103)
local root=p.Character:FindFirstChild("HumanoidRootPart")
local braid=R.Creature.creatures[R.Creature.order[1]]
local senses=R.Monster.Senses
check(senses.DirectSightStuds==90 and senses.ThermalStuds==22 and senses.LastKnownSeconds==8,
 "sight/heat/memory ranges are authored config, not infinite nearest-player GPS")
local structures={}
local wall={IsDescendantOf=function(_,parent) return parent==structures end}
local prop={IsDescendantOf=function() return false end}
local block=nil
local sensorRays=0
R.Creature.Structures=structures
R.Creature.Navigation={
 hit=function() sensorRays=sensorRays+1;return block and {Instance=block} or nil end,
 clear=function() sensorRays=sensorRays+1;return block==nil end,
 route=function(_,x,z,tx,tz) return tx,tz end,
}
local function place(dx,dz)
 root.Position={X=braid.X+dx,Y=braid.Y,Z=braid.Z+dz}
end
local t=R.Time
t.phase="Night";R.DayPrep:onPhaseChanged("Night");R.Floodlight:onPhaseChanged("Night")
place(180,0)
local seen=R.Creature:_nearestTarget(braid)
check(seen==nil,"unobstructed player across town is not precisely located")
R.Creature:think(.2)
check(braid.TargetX~=nil and braid.SearchMode=="patrol" and braid.TargetX~=root.Position.X,
 "without any clue, the Night Braid patrols its own bounded area instead of GPS-ing a hidden player")
place(40,0);seen=R.Creature:_nearestTarget(braid)
check(seen==root,"eye-less clear directional sensing notices nearby exposed prey")
local beforeVisible=sensorRays
R.Creature:think(.2)
check(sensorRays-beforeVisible==1,
 "real sensed clear prey reuses its ONE sight ray for chase, not a duplicate visibility ray")
local lastX=braid.LastKnownPosition.X
check(braid.TargetX==lastX,"observed prey position becomes bounded last-known area")
block=wall;place(60,0)
seen=R.Creature:_nearestTarget(braid)
check(seen==nil,"solid building wall occludes distant and close sight")
R.Creature:think(.2)
check(braid.TargetX==lastX and braid.TargetX~=root.Position.X,
 "behind wall Braid searches LAST SEEN spot, not hidden live coordinates")
t.elapsedTotal=t.elapsedTotal+9
R.Creature:think(.2)
check(braid.TargetX==nil,"last-known position expires instead of persisting forever")
block=prop;place(15,0)
seen=R.Creature:_nearestTarget(braid)
check(seen==root,"nearby body heat can register through a small nonstructural prop")
block=wall;seen=R.Creature:_nearestTarget(braid)
check(seen==nil,"thermal cannot pierce a solid structure even at close range")
-- WP6 first instinct-only investigation: only REAL recent emitted noise,
-- never a far hidden survivor's continuously sampled live coordinates.
block=nil;place(180,0)
local t0=t.elapsedTotal or 0
local farId=R.Noise:emitAt("VIBRATION",braid.X+75,braid.Y,braid.Z,3,t0)
R.Creature:think(.2)
check(braid.TargetX~=root.Position.X and braid.TargetX~=braid.X+75 and not braid.CoverExitIntent,
 "out-of-range sound never replaces the bounded patrol with a remote location")
local weakId=R.Noise:emitAt("VIBRATION",braid.X+19.3,braid.Y,braid.Z+3.7,.02,t0)
R.Creature:think(.2)
check(braid.SearchNoiseId~=weakId and not braid.CoverExitIntent,
 "below-threshold noise cannot replace the search/patrol target")
R.Noise:remove("VIBRATION",weakId)
local nx,ny,nz=braid.X+19.3,braid.Y,braid.Z+3.7
local soundId=R.Noise:emitAt("VIBRATION",nx,ny,nz,1,t0)
R.Creature:think(.2)
local cell=R.Monster.Memory.CellSize
local coarseX,coarseZ=math.floor(nx/cell+.5)*cell,math.floor(nz/cell+.5)*cell
check(braid.TargetX==coarseX and braid.TargetZ==coarseZ
 and braid.TargetX~=root.Position.X and not braid.CoverExitIntent,
 "nearby emitted vibration yields a coarse investigation target, not live prey GPS or cover damage")
place(210,0);R.Creature:think(.2)
check(braid.TargetX==coarseX and braid.TargetZ==coarseZ,
 "moving a silent hidden player never updates the already heard sound location")
R.Noise:remove("VIBRATION",soundId);R.Creature:think(.2)
check(braid.SearchMode=="sweep" and braid.TargetX~=root.Position.X
 and not braid.CoverExitIntent,
 "removed noise hands off to local clue sweep, not a phantom live prey target")
block=wall
local blockedId=R.Noise:emitAt("VIBRATION",nx,ny,nz,1,t0)
R.Creature:think(.2)
check(braid.NoiseInvestigatedId==blockedId and braid.TargetX~=coarseX
 and not braid.CoverExitIntent,
 "a sound behind a solid structure cannot pull the Braid straight through a wall")
R.Noise:remove("VIBRATION",blockedId);block=nil
local atFeet=R.Noise:emitAt("VIBRATION",braid.X+3,braid.Y,braid.Z,1,t0)
R.Creature:think(.2)
check(braid.NoiseInvestigatedId==atFeet and braid.SearchMode=="sweep"
 and braid.TargetX~=root.Position.X,
 "reaching the emitted impulse starts a local sweep without revealing the hidden player")
local secondId=R.Noise:emitAt("VIBRATION",nx,ny,nz,1,t0)
R.Creature:think(.2)
check(secondId~=atFeet and braid.TargetX==coarseX,
 "a new real impulse remains investigable after the first one is dismissed")
R.Noise:remove("VIBRATION",atFeet);R.Noise:remove("VIBRATION",secondId)
local staleId=R.Noise:emitAt("VIBRATION",nx,ny,nz,1,t0)
t.elapsedTotal=t0+9
R.Creature:think(.2)
check(braid.SearchNoiseId~=staleId and braid.TargetX~=root.Position.X
 and not braid.CoverExitIntent,
 "stale vibration cannot become hidden-prey memory; Night search continues independently")
R.Noise:remove("VIBRATION",staleId);R.Noise:remove("VIBRATION",farId)
place(20,0)
R.Noise:emitAt("VIBRATION",nx,ny,nz,2,t.elapsedTotal)
R.Creature:think(.2)
check(braid.CoverPreyX==root.Position.X and braid.TargetX==root.Position.X,
 "genuinely sensed nearby living prey still outranks a louder emitted noise")
block=prop;place(15,0)
local beforeHeat=sensorRays
R.Creature:think(.2)
check(sensorRays-beforeHeat==1 and braid.DecisionReason=="genuinely-sensed-prey",
 "thermal-through-prop sensing reuses a blocked ray without falsely calling it clear")
local nearPlayer=R.Players:addPlayer("CloserThermalPrey",50104)
local nearRoot=nearPlayer.Character:FindFirstChild("HumanoidRootPart")
place(40,0) -- farther player is visibly clear
nearRoot.Position={X=braid.X+15,Y=braid.Y,Z=braid.Z}
local hit=R.Creature.Navigation.hit
R.Creature.Navigation.hit=function(self,ax,az,tx,tz,params)
 block=tx==nearRoot.Position.X and prop or nil
 return hit(self,ax,az,tx,tz,params)
end
local nearest,chosen,_,clear=R.Creature:_nearestTarget(braid)
check(nearest==nearRoot and chosen==nearPlayer and clear==false,
 "near blocked thermal prey replaces far clear prey WITHOUT inheriting its clear flag")
return SESSION
