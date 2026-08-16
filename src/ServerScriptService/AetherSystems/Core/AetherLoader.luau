local RS = game:GetService("ReplicatedStorage")

local Logger = require(RS.AetherShared.Utils.Logger)
local SystemManager = require(script.SystemManager)

local AetherLoader = {}

local _ready = false
local _bootError = nil

Logger:Banner("AetherSystems-Framework V.1.1.0")
Logger:Debug("AetherLoader", "Initializing Systems")

local _ok, _err = pcall(SystemManager.Init)
if _ok then
	_ready = true
else
	_bootError = tostring(_err)
	Logger:Warn("AetherLoader", "Boot failed: " .. _bootError)
end

-- IMPORTANT: public API must go through the Loader only

function AetherLoader.Get(name)
	if _bootError then
		error("[AetherLoader] Boot failed, cannot Get('" .. tostring(name) .. "'): " .. _bootError, 2)
	end

	while not _ready do
		task.wait()
	end

	return SystemManager.Get(name)
end

function AetherLoader.List()
	if _bootError then
		error("[AetherLoader] Boot failed, cannot List(): " .. _bootError, 2)
	end

	while not _ready do
		task.wait()
	end

	return SystemManager.List()
end

function AetherLoader.IsReady()
	return _ready
end

return AetherLoader