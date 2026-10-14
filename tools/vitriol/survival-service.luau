-- Offline ownership and Health seam regression for the UNWIRED M6 service.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local function approx(a,b) return math.abs(a-b)<1e-8 end
local Config=VitriolRequire("SurvivalConfig")
local Service=VitriolRequire("SurvivalService")
local missing=pcall(function() Service:init({Players={},Health={},Survival=Config}) end)
check(not missing,"initialization refuses absent server-verified samplers")
local players={list={},GetPlayers=function(self)return self.list end}
local health={states={},calls={}}
function health:metersAllowRegen(id,ok)
 self.calls[#self.calls+1]={id=id,ok=ok}
 local state=self.states[id]
 if state then state.metersAllowRegen=ok end
end
local activities={[801]="Walking",[802]="Sprinting"}
local environs={[801]={hot=true,bleeding=false,health=0,collapsed=true},[802]={}}
local svc=setmetatable({},Service)
local beforeHeartbeats=COUNTERS.heartbeatConnections
local beforeRemote=COUNTERS.remoteFires
local beforeInstances=COUNTERS.runtimeInstanceNew
svc:init({Players=players,Health=health,Survival=Config,
 ResolveActivity=function(player) return activities[player.UserId] end,
 ResolveEnvironment=function(player) return environs[player.UserId] end})
check(next(svc.models)==nil and COUNTERS.heartbeatConnections==beforeHeartbeats,
 "init creates no player meters or scheduler/Heartbeat/cadence job")
local p={UserId=801,Name="owner",Character={}}
local q={UserId=802,Name="other",Character={}}
local forged={UserId=801,Name="stale",Character={}}
check(svc:observe(forged)==nil and next(svc.models)==nil,
 "an unregistered Player object cannot allocate another player's ledger")
players.list={p,q}
health.states[801]={player=p,character=p.Character,
 root={Position={X=1,Y=2,Z=3}},bleedRate=.4,humanoid={Health=75},dead=false}
health.states[802]={player=q,character=q.Character,
 root={Position={X=5,Y=2,Z=6}},bleedRate=0,humanoid={Health=55},dead=false}
local entry=svc:observe(p)
check(entry and svc:observe(p)==entry and svc:observe(q)~=entry,
 "observe allocates one distinct run ledger per legitimate UserId")
for _,dt in ipairs({-1,0/0,math.huge,5.1}) do
 local applied,why=svc:pulse(dt)
 check(applied==nil and why=="invalid-dt" and entry.model.state.thirst==0,
  "invalid dt rejects the full server tick without changing any ledger")
end
local advanced,reason=svc:pulse(1)
local other=svc.models[802]
check(advanced==2 and reason==nil and other and
 approx(entry.model.state.thirst,.8*1.35*1.25/60) and
 approx(entry.model.state.hunger,.42*1.10*1.05/60) and
 approx(other.model.state.thirst,2.1/60),
 "two players advance separately from server activity and wound/environment facts")
local snap=svc:snapshot(p)
check(snap and snap.thirst==entry.model.state.thirst and snap.hunger==entry.model.state.hunger
 and snap.debuffs[1]=="Bleeding" and svc:snapshot(q).debuffs[1]==nil
 and not entry.conditions.collapsed and entry.conditions.health==75,
 "environment cannot spoof bleeding, live HP or collapse; owner snapshots do not contain rival data")
check(health.states[801].humanoid.Health==75 and health.states[802].humanoid.Health==55
 and health.states[801].metersAllowRegen and health.states[802].metersAllowRegen,
 "service uses Health regen flag without becoming another HP writer")
snap.debuffs[1]="FAKE";snap.thirst=900
check(svc:snapshot(p).debuffs[1]=="Bleeding" and svc:snapshot(p).thirst<100,
 "a returned snapshot cannot mutate a server-owned ledger or effects list")
entry.model.state.thirst=70
svc:pulse(.2)
check(not health.states[801].metersAllowRegen and health.states[802].metersAllowRegen,
 "Health regen gate uses post-step coupling threshold separately for each player")
local prev=other.model.state.thirst
activities[802]="Teleporting"
advanced,reason=svc:pulse(.2)
check(advanced==1 and reason=="rejected-sampler" and
 other.model.state.thirst==prev and not health.states[802].metersAllowRegen,
 "invalid server activity rejects only that player's step and fails regen closed")
activities[802]="Walking";environs[802]=false
advanced,reason=svc:pulse(.2)
check(advanced==1 and reason=="rejected-sampler" and other.model.state.thirst==prev
 and not health.states[802].metersAllowRegen,
 "invalid environment sampler cannot silently advance another player's needs")
environs[802]={}
health.states[802].dead=true
advanced=svc:pulse(1)
check(advanced==1 and other.model.state.thirst==prev and not health.states[802].metersAllowRegen,
 "dead players neither drain needs nor receive a health-regeneration grant")
health.states[802].dead=false;health.states[802].awaitingDawn=true
advanced=svc:pulse(1)
check(advanced==1 and other.model.state.thirst==prev,
 "players waiting for the approved dawn respawn do not advance the meter")
health.states[802].awaitingDawn=false;health.states[802].humanoid.Health=0
advanced=svc:pulse(1)
check(advanced==1 and other.model.state.thirst==prev,
 "a zero-health humanoid cannot spend survival time before Health resolves death")
health.states[802].humanoid.Health=55
health.states[802].permadead=true
advanced=svc:pulse(1)
check(advanced==1 and other.model.state.thirst==prev and svc:snapshot(q)==nil,
 "permadead player cannot advance survival or read an active-life snapshot")
health.states[802].permadead=false
players.list={q}
check(svc:snapshot(p)==nil,
 "a player no longer in Players cannot read a stale cached ledger even before detach")
players.list={p,q}
local saved=entry.model.state.thirst
svc:detach(p)
check(svc:snapshot(p)==nil and svc:snapshot(forged)==nil and svc.models[801].model.state.thirst==saved
 and not health.states[801].metersAllowRegen,
 "disconnect revokes snapshot/regen but retains run-local meters, no free hydration")
players.list={forged,q};health.states[801].player=forged
health.states[801].character=forged.Character
health.states[801].root={Position={X=11,Y=3,Z=-4}}
advanced=svc:pulse(1)
check(advanced==2 and svc.models[801]==entry and entry.player==forged
 and entry.model.state.thirst>saved and svc:snapshot(p)==nil and svc:snapshot(forged)~=nil,
 "reconnect uses same UserId ledger but only the new live Player receives a snapshot")
entry.model.state.thirst=100;entry.model.state.hunger=80
check(not svc:beginCollapse(p) and not svc:beginCollapse(q)
 and svc:beginCollapse(forged) and entry.model.state.stamina==0,
 "only the living, currently connected owner with genuine two-meter need can arm one fall")
local collapsedSnapshot=svc:snapshot(forged)
local hasCollapse=false
for _,name in ipairs(collapsedSnapshot.debuffs) do
 if name=="Collapse" then hasCollapse=true end
end
check(hasCollapse and not svc:beginCollapse(forged),
 "server-owned onset carries the configured Collapse debuff without repeat arming")
local notReady,why=svc:advanceCollapse(q,2)
check(notReady==nil and why=="not-armed" and svc:takeFallForNoise(q)==nil,
 "another healthy player cannot advance or take the owner's fall event")
local invalid,invalidWhy=svc:advanceCollapse(forged,-1)
check(invalid==nil and invalidWhy=="invalid-dt" and entry.collapse.phase=="Onset",
 "invalid collapse dt cannot manufacture an early body noise")
invalid,invalidWhy=svc:advanceCollapse(forged,5.1)
check(invalid==nil and invalidWhy=="invalid-dt" and entry.collapse.phase=="Onset",
 "server adapter refuses a huge catch-up tick rather than fast-forwarding the fall")
local fallen=svc:advanceCollapse(forged,1.5)
check(fallen and fallen.phase=="Crawl" and fallen.fallPending
 and svc:takeFallForNoise(p)==nil,
 "only the current player may take a real fall request after the onset")
local originalCharacter=forged.Character
forged.Character={};health.states[801].character=forged.Character
local stale,staleWhy=svc:advanceCollapse(forged,.2)
check(stale==nil and staleWhy=="stale-body" and svc:takeFallForNoise(forged)==nil
 and entry.collapse.fallPending,
 "a replaced character cannot advance or emit an earlier body's pending fall")
forged.Character=originalCharacter;health.states[801].character=originalCharacter
local realRoot=health.states[801].root
health.states[801].root=nil
check(svc:takeFallForNoise(forged)==nil and entry.collapse.fallPending,
 "a missing body root cannot spend the pending noise event")
health.states[801].root={Position={X=0/0,Y=2,Z=3}}
check(svc:takeFallForNoise(forged)==nil and entry.collapse.fallPending,
 "a non-finite body location cannot spend the pending noise event")
health.states[801].root=realRoot
realRoot.Position={X=12,Y=2,Z=-6}
local sound=svc:takeFallForNoise(forged)
check(sound and sound.channel=="VIBRATION" and sound.intensity==.9
 and sound.x==12 and sound.y==2 and sound.z==-6
 and svc:takeFallForNoise(forged)==nil,
 "one request uses the verified body's CURRENT location, not a hidden/player-clue coordinate")
svc:pulse(.2)
check(entry.model.state.stamina==0 and health.states[801].humanoid.Health==75,
 "an offline collapse cannot regenerate stamina or become a second Health writer")
other.model.state.thirst=100;other.model.state.hunger=80
check(svc:beginCollapse(q) and svc:advanceCollapse(q,1.5).fallPending,
 "second live player can independently have a pending physical fall")
local absent,absentWhy=svc:emitPendingFall(q)
check(not absent and absentWhy=="missing-emitter" and other.collapse.fallPending,
 "an unwired/no-Noise adapter refuses emission without consuming the sole fall")
svc:detach(q)
local newQ={UserId=802,Name="rejoined",Character={}}
players.list={forged,newQ}
health.states[802].player=newQ
health.states[802].character=newQ.Character
health.states[802].root={Position={X=900,Y=3,Z=900}}
svc:observe(newQ)
check(other==svc.models[802] and svc:takeFallForNoise(q)==nil
 and svc:takeFallForNoise(newQ)==nil and not other.collapse.fallPending,
 "disconnect discards a departed body's pending fall; reconnect cannot replay it elsewhere")
check(other.collapse.phase=="Crawl" and not svc:beginCollapse(newQ)
 and other.model.state.thirst==100,
 "disconnect does not reset critical needs/collapse to bypass its future recovery policy")
local newSnapshot=svc:snapshot(newQ)
local stillCollapsed=false
for _,name in ipairs(newSnapshot.debuffs) do if name=="Collapse" then stillCollapsed=true end end
check(stillCollapsed and svc:snapshot(q)==nil,
 "a rejoined owner immediately sees the server's active collapse, not stale cached pulse flags")
check(COUNTERS.remoteFires==beforeRemote and COUNTERS.runtimeInstanceNew==beforeInstances
 and COUNTERS.heartbeatConnections==beforeHeartbeats,
 "offline adapter sends no remote, constructs no Instance and registers no live work")
-- Automatic COLLAPSE math under an explicitly invoked server pulse. The
-- noise sink below is a spy, not a new client locator or a live scheduler.
local autoPlayer={UserId=803,Name="auto",Character={}}
local autoPlayers={list={autoPlayer},GetPlayers=function(self)return self.list end}
local autoRoot={Position={X=1,Y=2,Z=3}}
health.states[803]={player=autoPlayer,character=autoPlayer.Character,
 root=autoRoot,bleedRate=0,humanoid={Health=100},dead=false}
local autoActivity="Walking"
local noiseSpy={events={}}
function noiseSpy:emitAt(channel,x,y,z,intensity,now)
 self.events[#self.events+1]={channel=channel,x=x,y=y,z=z,intensity=intensity,now=now}
 return #self.events
end
local auto=setmetatable({},Service)
auto:init({Players=autoPlayers,Health=health,Survival=Config,Noise=noiseSpy,
 Time={elapsedTotal=12.3},ResolveActivity=function()return autoActivity end,
 ResolveEnvironment=function()return {} end})
auto:pulse(.2)
check(auto.models[803].collapse.phase=="Idle" and #noiseSpy.events==0,
 "ordinary server needs sampling does not arm a healthy player")
local autoEntry=auto.models[803]
autoEntry.model.state.thirst=100;autoEntry.model.state.hunger=80
auto:pulse(.2)
check(autoEntry.collapse.phase=="Onset" and autoEntry.collapse.onsetLeft==1.5
 and autoEntry.model.state.stamina==0 and #noiseSpy.events==0,
 "a genuine post-step candidate arms onset at tick END, with no premature noise")
auto:pulse(1)
check(autoEntry.collapse.phase=="Onset" and approx(autoEntry.collapse.onsetLeft,.5)
 and #noiseSpy.events==0,
 "the next real second advances onset but cannot emit early")
local existingChar=autoPlayer.Character
autoPlayer.Character={};health.states[803].character=autoPlayer.Character
auto:pulse(.25)
check(autoEntry.collapse.phase=="Onset" and approx(autoEntry.collapse.onsetLeft,.5)
 and #noiseSpy.events==0,
 "a replaced body cannot inherit or fast-forward the original onset")
autoPlayer.Character=existingChar;health.states[803].character=existingChar
autoRoot.Position=nil
autoActivity="Teleporting"
local moved,whyAuto=auto:pulse(.5)
check(moved==0 and whyAuto=="rejected-sampler"
 and autoEntry.collapse.phase=="Crawl" and autoEntry.collapse.fallPending
 and #noiseSpy.events==0,
 "real collapse time still reaches fall despite an invalid activity, but absent root blocks noise")
autoRoot.Position={X=4,Y=5,Z=6}
autoActivity="Walking"
auto:pulse(.2)
local emittedSpy=noiseSpy.events[1]
check(#noiseSpy.events==1 and emittedSpy.channel=="VIBRATION"
 and emittedSpy.intensity==.9 and emittedSpy.x==4 and emittedSpy.y==5
 and emittedSpy.z==6 and emittedSpy.now==12.3,
 "the retried REAL fall emits once from the current attached body, not the onset location")
auto:pulse(2)
check(#noiseSpy.events==1 and not autoEntry.collapse.fallPending
 and autoEntry.model.state.stamina==0,
 "continued critical needs/crawl cannot duplicate the fall or restore sprint stamina")
-- Also exercise the REAL existing HealthService seam under the session shim,
-- not only the small fake above. This does not wire Survival into Bootstrap.
local runtime=VitriolRequire("Bootstrap").ensure()
local realPlayer=runtime.Players:addPlayer("OfflineSurvivor",90217)
local realHealth=runtime.Health.states[realPlayer.UserId]
check(realHealth and realHealth.humanoid and realHealth.metersAllowRegen==false,
 "headless Bootstrap supplies a real Health ledger with survival regen initially off")
local live=setmetatable({},Service)
live:init({Players=runtime.Players,Health=runtime.Health,Survival=Config,
 Noise=runtime.Noise,Time=runtime.Time,
 ResolveActivity=function()return "Walking" end,
 ResolveEnvironment=function()return {} end})
local ownHp=realHealth.humanoid.Health
local connBefore=COUNTERS.heartbeatConnections
local numBefore=COUNTERS.runtimeInstanceNew
local remBefore=COUNTERS.remoteFires
advanced=live:pulse(.2)
check(advanced==1 and realHealth.metersAllowRegen==true
 and realHealth.humanoid.Health==ownHp and live:snapshot(realPlayer).thirst>0,
 "adapter drives ACTUAL HealthService regen seam without writing Humanoid HP")
local liveModel=live.models[realPlayer.UserId].model
liveModel.state.thirst=70
live:pulse(.2)
check(realHealth.metersAllowRegen==false and liveModel.state.thirst>70,
 "real HealthService regen flag disables at the crossed configured meter threshold")
liveModel.state.thirst=100;liveModel.state.hunger=80
check(live:beginCollapse(realPlayer) and live:advanceCollapse(realPlayer,1.5).fallPending,
 "real Health/character ownership arms one genuine fall on the headless player")
local oldRoot=realHealth.root
local idBeforeBlock=runtime.Noise.nextId.VIBRATION
realHealth.root=nil
local blocked,blockedWhy=live:emitPendingFall(realPlayer)
check(not blocked and blockedWhy=="not-pending"
 and live.models[realPlayer.UserId].collapse.fallPending
 and runtime.Noise.nextId.VIBRATION==idBeforeBlock,
 "real NoiseField cannot receive the request without an attached body root")
realHealth.root=oldRoot
realHealth.dead=true
blocked,blockedWhy=live:emitPendingFall(realPlayer)
check(not blocked and blockedWhy=="not-pending"
 and live.models[realPlayer.UserId].collapse.fallPending
 and runtime.Noise.nextId.VIBRATION==idBeforeBlock,
 "a dead HealthService life cannot emit a delayed survival fall")
realHealth.dead=false
local originalTime=live.Time
live.Time={}
local refused,refusedWhy=live:emitPendingFall(realPlayer)
check(not refused and refusedWhy=="missing-emitter"
 and live.models[realPlayer.UserId].collapse.fallPending,
 "a missing server timestamp leaves the real body's pending fall intact")
live.Time=originalTime
local originalNoise=live.Noise
live.Noise={emitAt=function()return nil end}
refused,refusedWhy=live:emitPendingFall(realPlayer)
check(not refused and refusedWhy=="emit-rejected"
 and live.models[realPlayer.UserId].collapse.fallPending,
 "a rejected impulse does not spend the one-shot event")
live.Noise=originalNoise
local pos=realHealth.root.Position
local previousId=runtime.Noise.nextId.VIBRATION
local emitted,emitWhy=live:emitPendingFall(realPlayer)
check(emitted and emitWhy==nil and runtime.Noise.nextId.VIBRATION==previousId+1
 and runtime.Noise:sample("VIBRATION",pos.X,pos.Y,pos.Z,5,runtime.Time.elapsedTotal)>=.9,
 "REAL NoiseField receives one configured 0.9 VIBRATION at the living body's position")
emitted,emitWhy=live:emitPendingFall(realPlayer)
check(not emitted and emitWhy=="not-pending"
 and runtime.Noise.nextId.VIBRATION==previousId+1
 and live:takeFallForNoise(realPlayer)==nil,
 "the second emit/retrieve cannot duplicate the real fall impulse")
check(COUNTERS.heartbeatConnections==connBefore and COUNTERS.runtimeInstanceNew==numBefore
 and COUNTERS.remoteFires==remBefore,
 "real-Health test confirms no extra work or outbound traffic from the adapter")
runtime.Players:removePlayer(realPlayer)
live:detach(realPlayer)
VitriolRequire("Bootstrap").stop()
print("Survival service: "..SESSION.passed.." passed, "..SESSION.failed.." failed")
return SESSION
