--!strict
-- VehicleConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > VehicleConfig  (ModuleScript)
-- Purpose:  Drivetrain, suspension, fuel, damage and - critically - the noise the
--           vehicle emits, because a car is the loudest thing in the game
--           (docs/07-DESTRUCTION-VEHICLES.md §3).
-- Requires: (none)
-- Used by:  Services/VehicleService, Client/VehicleController

local VehicleConfig = {}

-- Implementation selector (docs/07 §3.1). "VehicleSeat" is the MVP path;
-- "Custom" is the target and sits behind a flag until it is tuned.
VehicleConfig.Controller = "VehicleSeat"
VehicleConfig.AllowCustomController = false

VehicleConfig.Defaults = {
	MaxSpeed = 48, -- studs/s
	Torque = 22,
	TurnSpeed = 6,
	-- Custom controller only:
	DriveForce = 9000,
	SteerRate = 2.2,
	DownforceK = 12, -- -Y * k * |v|^2, so grip rises with speed and crashes hurt
	MaxSteerAngleDeg = 32,
}

-- Suspension: TorsionSpringConstraint (docs/08 §3.4).
-- NOTE: CurrentAngle is NOT replicated - never read it on a client for gameplay.
VehicleConfig.Suspension = {
	Stiffness = 900,
	Damping = 220,
	LimitsEnabled = true,
	MaxAngle = 18,
	Restitution = 0.1,
	Radius = 0.4,
	MaxTorque = 4000,
}

VehicleConfig.Wheels = {
	Radius = 1.4,
	Width = 0.9,
	Friction = { Asphalt = 1.0, Concrete = 0.95, Grass = 0.6, Sand = 0.45, Mud = 0.35 },
	Massless = false,
}

VehicleConfig.Fuel = {
	Capacity = 40,
	DrainPerSecondAtFullThrottle = 0.55,
	DrainIdle = 0.02,
	WarningAt = 0.2, -- fraction
}

VehicleConfig.Health = {
	Max = 300,
	WreckedAt = 0, -- still usable as a barricade, cannot drive
	ImpactDamageScale = 0.03,
	CreatureImpactDamageScale = 0.5, -- hitting the creature hurts the car too
}

-- Noise emission. Driving is a broadcast (docs/00-VISION.md P3).
VehicleConfig.Noise = {
	EngineAirPerRpm = 0.9, -- scaled by throttle/rpm 0..1
	TyreVibrationPerSpeed = 0.02, -- per stud/s, scaled by surface friction
	ImpactVibrationReference = 4000, -- energy that reads as 1.0
	HornAir = 1.0,
	-- Headlights are an EM emitter: lights off is quieter to the creature but you
	-- cannot see. This trade-off is intentional and permanent.
	HeadlightsEm = 0.6,
	RadioEm = 0.9,
	EngineThermal = 0.4,
}

VehicleConfig.Seats = {
	DriverSeatName = "DriverSeat",
	EnterRange = 8,
	ExitImpulse = 0,
	AutoAssignOwnership = true,
}

return VehicleConfig
