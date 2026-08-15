local RS = game:GetService("ReplicatedStorage")
local _SSS = game:GetService("ServerScriptService")

local Discovery = require(script:FindFirstChild("Discovery") or script.Parent:FindFirstChild("Discovery"))
local Resolver = require(script:FindFirstChild("Resolver") or script.Parent:FindFirstChild("Resolver"))
local Logger = require(RS:WaitForChild("AetherShared"):WaitForChild("Utils"):WaitForChild("Logger"))

local function dump(t)
	local out = {}
	for k,v in pairs(t) do table.insert(out, tostring(k)) end
	table.sort(out)
	return table.concat(out, ", ")
end

local entries = Discovery.Discover()
Logger:Info("Diagnostics", "Discovered entries:")
for i, e in ipairs(entries) do
	Logger:Info(
		"Diagnostics",
		string.format("folder=%s module=%s", e.Name, e.Module and e.Module.Name or "<nil>")
	)
end

local ok, ordered, registry = pcall(function()
	return Resolver.Resolve(entries)
end)

if not ok then
	Logger:Warn("Diagnostics", "Resolver failed:", ordered)
else
	Logger:Info("Diagnostics", "Resolved order:", table.concat(ordered, ", "))
	Logger:Info("Diagnostics", "Registry keys:", dump(registry))
end

return true
