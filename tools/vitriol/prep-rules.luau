local Rules = VitriolRequire("PrepRules")
TESTS = { passed = 0, failed = 0 }
local function check(ok, label)
	if ok then TESTS.passed = TESTS.passed + 1; print("PASS " .. label)
	else TESTS.failed = TESTS.failed + 1; print("FAIL " .. label) end
end
local function eq(a,b) return a ~= nil and math.abs(a-b) < 0.000001 end
check(Rules.VoteWindowSeconds == 3, "real helper voting window is three seconds")
check(eq(Rules.cost("BoardGarage",0,210,210),20), "garage costs 20 normal seconds")
check(eq(Rules.cost("BoardGarage",1,210,210),19), "one consenting helper saves one second")
check(eq(Rules.cost("BoardGarage",2,210,210),18), "two consenting helpers save two seconds")
check(eq(Rules.cost("BoardGarage",8,210,210),18), "helper discount is capped")
check(eq(Rules.cost("BoardGarage",0,10,10),20/21), "fast-test Day scales garage cost")
check(eq(Rules.cost("BoardGarage",2,10,10),18/21), "fast-test helper discount scales too")
check(eq(Rules.cost("BoardGarage",0,11,11),20*11/210), "a revised Studio test Day length scales without a hardcoded 10")
check(eq(Rules.cost("TakeFuel",0,210,210),4), "taking fuel also costs Day time")
check(eq(Rules.cost("PowerGarage",0,210,210),12), "powering lamp costs Day time")
check(eq(Rules.cost("PrimeBell",0,210,210),8), "priming bell costs Day time")
check(eq(Rules.cost("RepairStationFloodlight",0,210,210),16), "station light costs Day time")
check(eq(Rules.cost("RepairGarageLight",0,210,210),16), "broken garage light repair costs Day time")
check(eq(Rules.cost("BoardGarage",0,210,0.5),0.5), "Day spending cannot overshoot Dusk")
check(Rules.cost("Unknown",0,210,210)==nil, "unknown action is rejected")
check(Rules.cost("BoardGarage",-1,210,210)==nil, "invalid helpers rejected")
check(Rules.cost("BoardGarage",0,0,210)==nil, "nonpositive Day length rejected")
check(Rules.cost("BoardGarage",0,210,-1)==nil, "negative remaining budget rejected")
return TESTS
