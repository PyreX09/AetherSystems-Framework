local module = {}

local RS = game:GetService("ReplicatedStorage")
local Logger = require(RS.AetherShared.Utils.Logger)

local CATEGORY = "Resolver"

function module.Resolve(entries)
	assert(type(entries) == "table", "Resolver.Resolve expects an array of entries")

	local registry = {}
	local depsMap = {}

	Logger:Debug(CATEGORY, "Resolving", #entries, "system(s)")

	-- Load modules and extract descriptors
	for _, entry in ipairs(entries) do
		local ok, mod = pcall(require, entry.Module)

		if not ok then
			Logger:Fatal(CATEGORY, "Failed to require system", entry.Name, mod)
		end

		local name = entry.Name
		local descriptor = (type(mod) == "table" and mod.Descriptor) or nil

		if descriptor
			and descriptor.Name
			and type(descriptor.Name) == "string"
		then
			name = descriptor.Name
		end

		if registry[name] then
			Logger:Fatal(CATEGORY, "Duplicate system name detected", name, "(from folder", entry.Name .. ")")
		end

		registry[name] = {
			Module = mod,
			Descriptor = descriptor,
		}

		local deps = {}

		if descriptor and descriptor.Dependencies then
			for _, dependency in ipairs(descriptor.Dependencies) do
				table.insert(deps, dependency)
			end
		end

		depsMap[name] = deps
	end

	-- Build graph
	local indegree = {}
	local dependents = {}

	for name in pairs(registry) do
		indegree[name] = 0
		dependents[name] = {}
	end

	for name, deps in pairs(depsMap) do
		for _, dependency in ipairs(deps) do
			if not registry[dependency] then
				Logger:Fatal(CATEGORY, "Missing dependency", name, "->", dependency)
			end

			indegree[name] += 1
			table.insert(dependents[dependency], name)
		end
	end

	-- Kahn's algorithm
	local queue = {}

	for name, degree in pairs(indegree) do
		if degree == 0 then
			table.insert(queue, name)
		end
	end

	table.sort(queue)

	local ordered = {}

	while #queue > 0 do
		local name = table.remove(queue, 1)
		table.insert(ordered, name)

		for _, dependent in ipairs(dependents[name]) do
			indegree[dependent] -= 1

			if indegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end

		table.sort(queue)
	end

	-- Cycle detection
	local total = 0

	for _ in pairs(registry) do
		total += 1
	end

	if #ordered ~= total then
		local remaining = {}

		for name, degree in pairs(indegree) do
			if degree > 0 then
				table.insert(remaining, name)
			end
		end

		table.sort(remaining)

		Logger:Fatal(CATEGORY, "Dependency cycle detected", table.concat(remaining, ", ")
		)
	end

	Logger:Info(CATEGORY, "Resolved", #ordered, "system(s)")
	return ordered, registry
end

return module