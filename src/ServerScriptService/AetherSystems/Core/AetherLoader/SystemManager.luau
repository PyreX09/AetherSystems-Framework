local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")

local Logger = require(RS.AetherShared.Utils.Logger)

local SystemManager = {}

local _registry = {}
local _ready = false

local function requireSiblingOrChild(name)
	local inst = script:FindFirstChild(name)
	if not inst and script.Parent then
		inst = script.Parent:FindFirstChild(name)
	end
	if not inst then
		Logger:Error("SystemManager", "Module missing:" .. name)
	end
	local ok, result = pcall(require, inst)
	if not ok then
		Logger:Error("SystemManager", "Failed to require module '" .. name .. "': " .. tostring(result))
	end
	return result
end

local Discovery = requireSiblingOrChild("Discovery")
local Resolver = requireSiblingOrChild("Resolver")
local LoaderMod = requireSiblingOrChild("Loader")

function SystemManager.Init()
	if _ready then
		warn("[SystemManager] Already initialized")
		return
	end

	-- Discovery -> Resolve -> Load
	local entries = Discovery.Discover()
	local orderedNames, registry = Resolver.Resolve(entries)
	LoaderMod.LoadOrdered(orderedNames, registry, _registry)

	_ready = true
	Logger:Info("SystemManager", "Ready")
end

function SystemManager.Get(name: string)
	assert(_ready, "[SystemManager] Not initialized yet - call Init() first")
	assert(name, "[SystemManager] System name cannot be nil")

	if not _registry[name] then
		Logger:Error("SystemManager", "System not found: " .. name .. " | Available: " .. table.concat(SystemManager.List(), ", "))
	end

	return _registry[name]
end

function SystemManager.List()
	local t = {}
	for k in pairs(_registry) do
		table.insert(t, k)
	end
	table.sort(t)
	return t
end

function SystemManager.IsReady()
	return _ready
end

return SystemManager