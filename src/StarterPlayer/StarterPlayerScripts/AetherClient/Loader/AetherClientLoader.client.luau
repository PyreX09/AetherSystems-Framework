--[[
	AetherClientLoader — Client Central Loader
	Aether Network System

	LocalScript entry point for all AetherClient systems.
	Scans Systems/ (and Services/), requires the primary module in each folder,
	resolves Dependencies, then calls Init(services) in topological order.

	PRIMARY MODULE CONVENTION
	  Loader looks for the primary module in this order:
	    1. ModuleScript named exactly "{FolderName}"        e.g. Network/Network
	    2. ModuleScript named "{FolderName}Client"         e.g. Tween/TweenClient
	    3. ModuleScript named "{FolderName}Server"         e.g. Network/NetworkServer (edge case)
	    4. First ModuleScript in folder sorted by name     (deterministic fallback)

	  Extra modules inside a folder (Utils, Helpers, etc.) are NOT loaded
	  by the Loader — they exist only to be required by the primary module.

	DEPENDENCY DECLARATION
	  Systems declare their own dependencies:

	    local MySystem = {}
	    MySystem.Dependencies = { "Network" }

	  Loader resolves the graph and guarantees Init() order.
	  No central load list to maintain.

	SERVICE INJECTION
	  Loader passes a `services` table into Init() containing all resolved modules:

	    function MySystem.Init(services)
	        local Network = services.Network
	        Network.On("DoorOpen", handler)
	    end

	  `services` contains only successfully loaded systems.
	  No WaitForChild or path traversal needed inside business logic.

	MISSING DEPENDENCY POLICY
	  If system A declares dependency "X" but "X" is not in the registry,
	  system A is marked invalid and skipped entirely (no Init).
	  This fails loudly at boot rather than silently at runtime.
	  Propagates transitively: if B is invalid and A depends on B, A is also skipped.

	CIRCULAR DEPENDENCY DETECTION
	  If A depends on B and B depends on A, both are excluded from orderedNames.
	  Boot summary reports them by name so dev knows exactly what was not initialized.

	ADDING A NEW CLIENT SYSTEM
	  1. Create a Folder inside Systems/ (e.g. "Inventory")
	  2. Drop a ModuleScript named "InventoryClient" inside it
	  3. Declare Dependencies = { "Network" } if needed
	  4. Add Init(services) — use services.Network, services.Whatever
	  5. Done no changes needed here
]]

local AetherClient = script.Parent.Parent
local RS = game:GetService("ReplicatedStorage")
local Logger = require(RS.AetherShared.Utils.Logger)

-- === Step 1: Resolve primary module per folder ================================

--[[
	findPrimaryModule(folder) -> ModuleScript | nil

	Priority:
	  1. folder.Name              e.g. "Network"
	  2. folder.Name .. "Client"  e.g. "NetworkClient"
	  3. folder.Name .. "Server"  e.g. "NetworkServer"  (edge case)
	  4. first ModuleScript alphabetically (deterministic fallback)

	Extra helpers (Utils, Config, etc.) inside the folder are ignored here —
	they get required by the primary module itself if needed.
]]
local function findPrimaryModule(folder: Folder): ModuleScript?
	if not folder then
		Logger:Error("AetherClientLoader", "Folder is nil")
		return nil
	end

	local folderName = folder.Name

	local candidates = {
		folderName,
		folderName .. "Client",
		folderName .. "Server",
	}

	for _, name in ipairs(candidates) do
		local found = folder:FindFirstChild(name)
		if found and found:IsA("ModuleScript") then
			return found
		end
	end

	local modules = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end

	if #modules == 0 then
		Logger:Debug("AetherClientLoader",
			"No ModuleScript found in folder: " .. folder.Name
		)
		return nil
	end

	table.sort(modules, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)

	Logger:Warn("AetherClientLoader",
		string.format(
			"No primary module found in %s, using fallback '%s'",
			folder.Name,
			modules[1].Name
		)
	)

	return modules[1]
end

-- === Step 2: Require all primary modules (no Init yet) =======================

-- registry[folderName] = { module = <table>, instance = <ModuleScript> }
-- invalid[folderName]  = reason string — systems that failed require
local registry: {[string]: {module: any, instance: ModuleScript}} = {}
local invalid: {[string]: string} = {}

local foldersToScan = {"Services", "Systems"}

for _, targetFolderName in ipairs(foldersToScan) do
	local rootFolder = AetherClient:FindFirstChild(targetFolderName)

	if rootFolder then
		for _, item in ipairs(rootFolder:GetChildren()) do
			local name = item.Name
			local target = nil

			if item:IsA("Folder") then
				target = findPrimaryModule(item)
			elseif item:IsA("ModuleScript") then
				target = item
			end

			if not target then
				continue
			end

			local ok, result = pcall(require, target)

			if ok then
				local systemName = name
				if type(result) == "table" and result.Descriptor and result.Descriptor.Name then
					systemName = result.Descriptor.Name
				end

				if registry[systemName] then
					Logger:Warn("AetherClientLoader", "Duplicate system name detected: " .. systemName)
				else
					registry[systemName] = { module = result, instance = target }
				end
			else
				Logger:Warn("AetherClientLoader", 
					string.format(
						"Require failed %s (%s): %s",
						name, target.Name, tostring(result)
					))
				invalid[name] = "require error: " .. tostring(result)
			end
		end
	end
end

-- === Step 3: Validate dependencies (fail loud, fail early) ===================

--[[
	validateDependencies(registry, invalid) -> validRegistry, skipped

	If system A declares dependency "X" and X is missing or failed,
	A is skipped entirely. Propagates transitively until stable.
]]
local function validateDependencies(
	reg: {[string]: any},
	inv: {[string]: string}
): ({[string]: any}, {[string]: string})

	local skipped: {[string]: string} = {}

	for name, reason in pairs(inv) do
		skipped[name] = reason
	end

	local changed = true
	while changed do
		changed = false

		for name, entry in pairs(reg) do
			if skipped[name] then continue end

			local mod = entry.module
			local deps = (type(mod) == "table" and type(mod.Dependencies) == "table")
				and mod.Dependencies
				or (type(mod) == "table" and mod.Descriptor and type(mod.Descriptor.Dependencies) == "table" and mod.Descriptor.Dependencies)
				or {}

			for _, dep in ipairs(deps) do
				if skipped[dep] then
					local reason = string.format(
						"dependency '%s' is unavailable (%s)",
						dep, skipped[dep]
					)
					warn(string.format("[AetherClientLoader] Skipping %s — %s", name, reason))
					skipped[name] = reason
					changed = true
					break
				end

				if not reg[dep] then
					local reason = string.format("dependency '%s' not found in registry", dep)
					warn(string.format("[AetherClientLoader] Skipping %s — %s", name, reason))
					skipped[name] = reason
					changed = true
					break
				end
			end
		end
	end

	local valid = {}
	for name, entry in pairs(reg) do
		if not skipped[name] then
			valid[name] = entry
		end
	end

	return valid, skipped
end

local validRegistry, skippedSystems = validateDependencies(registry, invalid)

-- === Step 4: Build services table ============================================

--[[
	services[folderName] = module
	Loader passes this into every Init(services) call.
	Systems access their dependencies via services.Network, services.Whatever —
	no WaitForChild or path traversal inside business logic.
	Contains only successfully loaded systems (validRegistry).
]]
local services: {[string]: any} = {}
for name, entry in pairs(validRegistry) do
	services[name] = entry.module
end

-- === Step 5: Topological Sort =================================================

--[[
	topoSort(registry) -> orderedNames, cycledNames

	Kahn's algorithm — BFS using a head pointer instead of table.remove(queue, 1)
	  table.remove(t, 1) = O(N) shift of the whole array every time
	  head pointer = O(1) per step, doesn't touch memory layout

	COMPLEXITY
	  Traverse: O(V + E)
	    — each node is visited once, each edge is relaxed once
	  Sort: O(Σ Ki log Ki)
	    — Ki is the number of nodes unlocked together in each round
	    — not a single K, since newlyFree is sorted separately each round
	    — worst case still totals O(V log V) since Σ Ki = V
	  Total: O(V + E + V log V) = O((V + E) log V) for a typical sparse graph

	DETERMINISM
	  "topology deterministic" — not "lexicographically smallest topology"
	  seed queue sort makes systems with no deps start in name order
	  but the traversal queue isn't fully re-sorted during traversal
	  nodes unlocked later (D, F) always end up at the back of the queue, even if their name comes before B
	  example: A unlocks [D, F], D unlocks [B] → order = A D F B, not A B D F
	  for Aether (a few dozen systems, no deep dependency nesting) this is sufficient
	  a true lexicographic order would require switching to a priority queue (min-heap)

	Returns:
	  orderedNames  -- { "Network", "Tween", ... } in init order
	  cycledNames   -- systems with inDegree > 0 after traversal = part of a cycle
	                -- empty table if there is no cycle
]]
local function topoSort(reg: {[string]: any}): ({string}, {string})
	local inDegree: {[string]: number} = {}
	local dependents: {[string]: {string}} = {}

	for name in pairs(reg) do
		inDegree[name] = 0
		dependents[name] = {}
	end

	for name, entry in pairs(reg) do
		local mod = entry.module
		local deps = (type(mod) == "table" and type(mod.Dependencies) == "table")
			and mod.Dependencies
			or (type(mod) == "table" and mod.Descriptor and type(mod.Descriptor.Dependencies) == "table" and mod.Descriptor.Dependencies)
			or {}

		for _, dep in ipairs(deps) do
			inDegree[name] += 1
			table.insert(dependents[dep], name)
		end
	end

	-- seed queue sorted for determinism
	local queue = {}
	for name, deg in pairs(inDegree) do
		if deg == 0 then table.insert(queue, name) end
	end
	table.sort(queue)

	local ordered = {}

	-- head pointer instead of table.remove(queue, 1) — O(1) per step
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1

		table.insert(ordered, current)

		local newlyFree = {}
		for _, dependent in ipairs(dependents[current] or {}) do
			inDegree[dependent] -= 1
			if inDegree[dependent] == 0 then
				table.insert(newlyFree, dependent)
			end
		end

		if #newlyFree > 0 then
			table.sort(newlyFree)
			for _, name in ipairs(newlyFree) do
				table.insert(queue, name)
			end
		end
	end

	-- inDegree > 0 after traversal finishes = node is part of a cycle
	local cycled = {}
	for name in pairs(reg) do
		if inDegree[name] > 0 then
			table.insert(cycled, name)
		end
	end
	table.sort(cycled)

	return ordered, cycled
end

local orderedNames, cycledNames = topoSort(validRegistry)

-- === Step 6: Init in resolved order (with service injection) ==================

for _, name in ipairs(orderedNames) do
	local entry = validRegistry[name]
	local mod = entry.module
	local inst = entry.instance

	if type(mod) == "table" and type(mod.Init) == "function" then
		-- inject services — every Init receives the services table as its first arg
		-- if a system doesn't need services it can just do function(services) _ = services end
		local ok, err = pcall(mod.Init, services)
		if ok then
			Logger:Debug("AetherClientLoader", string.format("Started %s (%s)", name, inst.Name))
		else
			Logger:Warn("AetherClientLoader", string.format("Init failed %s: %s", name, tostring(err)))
		end
	else
		Logger:Debug("AetherClientLoader", string.format("Loaded %s (%s) [no Init]", name, inst.Name))
	end
end

-- === Step 7: Boot Summary =====================================================

local problems = {}

if #cycledNames > 0 then
	table.insert(problems, string.format(
		"circular dependency — NOT initialized: %s",
		table.concat(cycledNames, ", ")
		))
end

local skippedNames = {}
for name in pairs(skippedSystems) do
	table.insert(skippedNames, name)
end
table.sort(skippedNames)

if #skippedNames > 0 then
	table.insert(problems, string.format(
		"missing/invalid dependencies — NOT initialized: %s",
		table.concat(skippedNames, ", ")
		))
end

if #problems > 0 then
	for _, msg in ipairs(problems) do
		Logger:Warn("AetherClient", msg)
	end
	Logger:Warn("AetherClientLoader", 
		string.format(
			"Boot complete with %d issue(s). See warnings above.", 
			#problems
		)
	)
else
	Logger:Info("AetherClientLoader", string.format(
		"Boot complete. %d system(s) initialized", 
		#orderedNames
		)
	)
end