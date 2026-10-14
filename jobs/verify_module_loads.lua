-- EDIT MODE ONLY: require Vitriol ModuleScripts to surface Studio-only load errors.
-- Only module definitions load here; do NOT start Bootstrap.ensure or Main.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play before this Edit-mode module-load check")
local HttpService = game:GetService("HttpService")
local roots = {
    game:GetService("ReplicatedStorage"):FindFirstChild("Vitriol"),
    game:GetService("ServerStorage"):FindFirstChild("Vitriol"),
    game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
}
local results = { ok = 0, errors = {}, skipped = 0 }
for _, root in ipairs(roots) do
    if root then
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("ModuleScript") then
                -- Avoid non-Vitriol bundles under StarterPlayer.
                if root.Name == "StarterPlayerScripts" and not descendant:IsDescendantOf(root:FindFirstChild("Vitriol")) then
                    results.skipped += 1
                else
                    local success, err = pcall(require, descendant)
                    if success then results.ok += 1 else
                        results.errors[#results.errors + 1] = { path = descendant:GetFullName(), error = tostring(err) }
                    end
                end
            end
        end
    end
end
return HttpService:JSONEncode(results)
