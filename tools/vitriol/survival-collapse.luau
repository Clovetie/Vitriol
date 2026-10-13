-- Pure M6 collapse onset/fall timing. No NoiseField, Part or UI here.
TESTS={passed=0,failed=0}
local function check(ok,msg)
 if ok then TESTS.passed=TESTS.passed+1;print("PASS  "..msg)
 else TESTS.failed=TESTS.failed+1;warn("FAIL  "..msg) end
end
local function approx(a,b)return math.abs(a-b)<1e-8 end
local config=VitriolRequire("SurvivalConfig")
local Sequence=VitriolRequire("SurvivalCollapse")
local Model=VitriolRequire("SurvivalModel")
local c=Sequence.new(config.Collapse)
check(c.phase=="Idle" and c:takeFall()==nil and c:advance(20).phase=="Idle",
 "idle sequence neither starts nor emits a noise request on its own")
check(not c:begin(false) and not c:begin(nil) and c.phase=="Idle",
 "a missing/non-true server eligibility verdict cannot begin a fall")
local safe=Model.new(config)
check(not c:begin(safe:collapseCandidate(100)) and c.phase=="Idle",
 "healthy sated player has no collapse onset")
safe.state.thirst=100;safe.state.hunger=80
check(c:begin(safe:collapseCandidate(100)) and not c:begin(true),
 "the authored two-meter threshold arms a single onset, not repeated falls")
for _,bad in ipairs({-1,0/0,math.huge,3601}) do
 local state,err=c:advance(bad)
 check(state==nil and err=="invalid-dt" and c.phase=="Onset"
  and c.onsetLeft==config.Collapse.OnsetDelaySeconds and not c.fallPending,
  "invalid dt does not advance onset or generate a false fall")
end
local before=c:advance(1.49)
check(before.phase=="Onset" and approx(before.onsetLeft,.01)
 and not before.fallPending and c:takeFall()==nil,
 "the player has not fallen at 1.49 of the authored 1.5 seconds")
local boundary=c:advance(.01)
check(boundary.phase=="Crawl" and approx(boundary.crawlLeft,8)
 and boundary.fallPending and not c:begin(true),
 "a split dt reaches the exact fall boundary and opens an eight-second crawl")
local event=c:takeFall()
check(event and event.channel=="VIBRATION" and approx(event.intensity,.9)
 and c:takeFall()==nil and not c.fallPending,
 "the configured 0.9 VIBRATION request can be taken ONCE after the fall")
event.intensity=0
check(c:takeFall()==nil,
 "mutating an event receipt cannot recreate or change a consumed event")
local during=c:advance(7.99)
check(during.phase=="Crawl" and approx(during.crawlLeft,.01)
 and c:takeFall()==nil,
 "crawl restriction remains for the full authored eight seconds without a second fall")
local hold=c:advance(.01)
check(hold.phase=="Hold" and hold.crawlLeft==0 and not c:begin(true)
 and c:takeFall()==nil,
 "after eight seconds the sequence holds for a recovery POLICY rather than auto-resetting")
local another=Sequence.new(config.Collapse)
another:begin(true)
local crossed=another:advance(20)
check(crossed.phase=="Hold" and crossed.fallPending,
 "a long valid step cannot skip the onset fall event while crossing the crawl window")
local delayed=another:takeFall()
check(delayed and delayed.channel=="VIBRATION" and delayed.intensity==.9
 and another:takeFall()==nil and another:advance(20).phase=="Hold",
 "a pending fall remains retrievable exactly once, even after another long tick")
local vanished=Sequence.new(config.Collapse)
vanished:begin(true);vanished:advance(1.5)
check(vanished:cancelPendingFall() and not vanished:cancelPendingFall()
 and vanished:takeFall()==nil,
 "a disappeared body discards its once-pending physical noise")
check(vanished.phase=="Crawl" and not vanished:begin(true),
 "canceling a body's noise does NOT clear its collapse or grant a reconnect reset")
local modest=Sequence.new(config.Collapse)
modest:begin(true);modest:advance(1.6)
check(modest.phase=="Crawl" and approx(modest.crawlLeft,7.9)
 and modest:takeFall().intensity==.9,
 "overshoot across onset is charged to crawl only for its remaining fraction")
local low=Model.new(config)
low.state.thirst=60;low.state.hunger=60
local healthSequence=Sequence.new(config.Collapse)
check(healthSequence:begin(low:collapseCandidate(14.9))
 and healthSequence:advance(1.5).fallPending,
 "low-HP and both-meter candidate uses the same deterministic one-fall timeline")
local authored={OnsetDelaySeconds=2,CrawlDurationSeconds=4,FallVibrationIntensity=.6}
local reconfigured=Sequence.new(authored)
reconfigured:begin(true);reconfigured:advance(2)
check(reconfigured:takeFall().intensity==.6
 and reconfigured:advance(4).phase=="Hold",
 "timing and vibration values come from config rather than magic constants")
for _,invalid in ipairs({
 {OnsetDelaySeconds=0,CrawlDurationSeconds=8,FallVibrationIntensity=.9},
 {OnsetDelaySeconds=1.5,CrawlDurationSeconds=-8,FallVibrationIntensity=.9},
 {OnsetDelaySeconds=1.5,CrawlDurationSeconds=8,FallVibrationIntensity=1.2},
}) do
 local ok=pcall(function() Sequence.new(invalid) end)
 check(not ok,"invalid authored collapse timing/intensity fails closed")
end
print("Survival collapse: "..TESTS.passed.." passed, "..TESTS.failed.." failed")
return TESTS
