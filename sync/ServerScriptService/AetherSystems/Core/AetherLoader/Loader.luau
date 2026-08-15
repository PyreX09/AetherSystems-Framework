local RS = game:GetService("ReplicatedStorage")

local Logger = require(RS.AetherShared.Utils.Logger)
local Loader = {}

-- Load systems in the resolved order. Pass a mutable `systemRegistry` that may
-- contain pre-registered core systems (e.g. Network). This function builds a
-- `services` table (shallow copy of systemRegistry) and injects it into each
-- module's `Init(services)` call. After successful Init the module is added to
-- both `services` and `systemRegistry` so later inits can access dependencies.
function Loader.LoadOrdered(orderedNames, registry, systemRegistry)
	local services = {}
	for k, v in pairs(systemRegistry or {}) do services[k] = v end

	for _, name in ipairs(orderedNames) do
		local node = registry[name]
		if not node then
			Logger:Error("Loader", "Missing registry entry for " .. tostring(name))
		end

		local mod = nil
		-- Support both registry[name] = { Module = mod } and registry[name] = mod (backcompat)
		if type(node) == "table" and node.Module ~= nil then
			mod = node.Module
		elseif type(node) == "table" and type(node.Init) == "function" then
			mod = node
		elseif type(node) == "table" and node.Descriptor and node.Descriptor.Name then
			-- Fallback: maybe module stored under Descriptor field; try Descriptor.Module
			mod = node.Module
		end

		if not mod then
			Logger:Error("Loader", "Registry entry for " .. tostring(name) .. " has no Module")
		end

		if type(mod.Init) == "function" then
			local ok, err = pcall(mod.Init, services)
			if not ok then
				Logger:Warn("Loader", string.format("Failed to initialize %s: %s", tostring(name), tostring(err)))
				-- Don't register a system that failed to init; skip it so a
				-- single bad system doesn't take the rest of the boot down.
				continue
			end
		end

		services[name] = mod
		systemRegistry[name] = mod
		Logger:Debug("Loader", "Loaded:", name)
	end
end

return Loader
