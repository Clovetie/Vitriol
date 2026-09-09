# BloodEngine dependency

This folder mirrors the upstream MIT BloodEngine v1.1.3 module supplied for Vitriol.
In the Roblox Explorer hierarchy, import the four Lua files as ModuleScripts under
`ReplicatedStorage > VModules > BloodEngine`, import `Assets.rbxm` as the `Assets`
child, and expose `init` as the `BloodEngine` ModuleScript (or keep it as `init`
inside a BloodEngine folder; Vitriol supports both layouts).

Vitriol reaches it only through `ReplicatedStorage > Vitriol > Shared > BloodAdapter`.
The shipped adapter uses `BloodEngine.new(settings):Emit(...)`, never `EmitAmount`,
and keeps the prototype at LOW intensity. Do not call this module directly from
health/gameplay code.

Upstream source: https://github.com/rotntake/BloodEngine
License: `LICENSE.txt` (MIT, copyright rotn, 2024).
