--[[
	NetworkCore Shared Transport Core
	Aether Network System

	Shared foundation between Network Server and Network Client.
	No server-only or client-only logic.

	Responsibilities:
	  - Transport refs (RemoteEvent / RemoteFunction)
	  - Debug logging (format follows spec)
	  - Packet validation
	  - Multi-handler registry + disconnect support
	  - Invoke registry + pcall isolation
]]

local NetworkCore = {}

-- === Inspector / Trace System ================================================

-- Stores recent network activity for debugging.
-- This is intentionally kept inside NetworkCore to avoid creating another system.
-- Trace is disabled by default and has no runtime cost when disabled.

NetworkCore.TraceEnabled = game:GetService("RunService"):IsStudio()

local TraceHistory = {}
local TRACE_LIMIT = 500


--[[
	Trace(data)

	Internal recording function.

	Stores lightweight metadata only:
	  - Direction
	  - Event name
	  - Target
	  - Timestamp

	Does NOT store arguments by default to prevent:
	  - Memory growth
	  - Sensitive game data logging
	  - Large Instance references
]]

local TraceIndex = 0

function NetworkCore.Trace(data)
	if not NetworkCore.TraceEnabled then
		return
	end

	TraceIndex += 1

	if TraceIndex > TRACE_LIMIT then
		TraceIndex = 1
	end

	data.Id = TraceIndex
	data.Time = os.clock()

	TraceHistory[TraceIndex] = data
end

--[[
	GetTrace()

	Returns a copy of recent network activity.
	Used by debugging tools or developer console.
]]

function NetworkCore.GetTrace()
	local result = {}

	for _,data in pairs(TraceHistory) do
		table.insert(result,data)
	end
	
	table.sort(result,function(a,b)
		return a.Id < b.Id
	end)
	
	return result
end


--[[
	ClearTrace()

	Clears all stored network history.
]]

function NetworkCore.ClearTrace()
	table.clear(TraceHistory)
	TraceIndex = 0
end

-- === Transport Refs ===========================================================

local Network = game:GetService("ReplicatedStorage"):WaitForChild("AetherShared"):WaitForChild("Event"):WaitForChild("Network")
local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("AetherShared"):WaitForChild("Utils"):WaitForChild("Logger"))

NetworkCore.Remote = Network:WaitForChild("Event") -- RemoteEvent
NetworkCore.Function = Network:WaitForChild("Function") -- RemoteFunction

-- === Helper ===================================================================

local function safe(v)
	if typeof(v) == "Instance" then
		return v:GetFullName()
	end
	return tostring(v)
end

-- === Debug Mode ===============================================================

-- Debug flag is local to each Lua VM environment.
-- NetworkServer.Debug does NOT affect NetworkClient.Debug.
-- Each side has its own module cache.

NetworkCore.Debug = false

local PREFIX = "[Aether.Network]"

--[[
	_log(action, eventName, target?)
	Format follows spec:
	  [Aether.Network] SEND DoorOpen -> Player1
	  [Aether.Network] RECV DoorOpen <- Player1
	  [Aether.Network] INVOKE GetInventory <- Player1
	  [Aether.Network] FLUSH DoorOpen <- SERVER (queued)
]]
function NetworkCore._log(action: string, eventName: string, target: string?)

	NetworkCore.Trace({
		Direction = action,
		Event = eventName,
		Target = target,
	})

	if not NetworkCore.Debug then 
		return 
	end

	if target then
		print(string.format(
			"%s %s %s %s",
			PREFIX,
			action,
			eventName,
			target
			))
	else
		print(string.format(
			"%s %s %s",
			PREFIX,
			action,
			eventName
			))
	end
end

-- === Packet Validation ========================================================

NetworkCore.MAX_EVENT_NAME_LEN = 64

--[[
	ValidateEventName — checked before every send
	reject: nil, non-string, empty string, table, bool, number, too long (> MAX_EVENT_NAME_LEN)
	context is used for the error message (e.g. "NetworkServer.Fire")
]]

function NetworkCore.ValidateEventName(eventName: any, context: string)

	if type(eventName) ~= "string" or #eventName == 0 then

		local message = string.format("[%s] eventName must be a non-empty string, got: %s (%s)", context, tostring(eventName), type(eventName))
		Logger:Warn("NetworkCore", message)
		error(message, 3)
	end

	if #eventName > NetworkCore.MAX_EVENT_NAME_LEN then
		local message = string.format("[%s] eventName exceeds max length of %d: %s", context, NetworkCore.MAX_EVENT_NAME_LEN, eventName)
		Logger:Warn("NetworkCore", message)
		error(message, 3)
	end
end

-- === Handler Registry =========================================================

--[[
	NewRegistry() -> Register, Dispatch

	Multi-handler: registry[eventName] = { handler1, handler2, ... }
	Every handler registered for the same event gets called
	This supports multiple systems listening to the same event, e.g.:
	  Network.On("PlayerDied", Analytics)
	  Network.On("PlayerDied", Effects)
	  Network.On("PlayerDied", State)

	Register(eventName, handler) -> disconnectFn
	  returns a function that unregisters only that handler
	  other handlers listening to the same event are unaffected

	Dispatch(eventName, ...)
	  calls every handler with its own pcall — error isolation
	  one handler crashing doesn't affect the others
]]
function NetworkCore.NewRegistry()
	-- registry[eventName] = { handler, handler, ... }
	local registry: {[string]: {(...any) -> ()}} = {}

	local function Register(eventName: string, handler): () -> ()
		NetworkCore.ValidateEventName(eventName, "NetworkCore.NewRegistry.Register")
		assert(type(handler) == "function",
			"[NetworkCore] handler must be a function")

		if not registry[eventName] then
			registry[eventName] = {}
		end

		table.insert(registry[eventName], handler)

		-- returns a disconnect function — removes only this handler
		local disconnected = false
		return function()
			if disconnected then return end
			disconnected = true

			local list = registry[eventName]
			if not list then return end

			for i = #list, 1, -1 do
				if list[i] == handler then
					table.remove(list, i)
					break
				end
			end

			-- cleanup: remove the key once the list is empty
			if #list == 0 then
				registry[eventName] = nil
			end
		end
	end

	local function Dispatch(eventName: string, ...)
		NetworkCore.ValidateEventName(eventName, "NetworkCore.NewRegistry.Dispatch")
		local list = registry[eventName]

		if not list or #list == 0 then
			Logger:Warn("NetworkCore",string.format("%s No handler for event:%s", PREFIX, eventName))
			return
		end

		local count = #list
		for i = 1, count do
			local handler = list[i]
			if not handler then continue end

			local ok, err = pcall(handler, ...)
			if not ok then
				Logger:Warn("NetworkCore",string.format("%s Handler error [%s]: %s", PREFIX, eventName, tostring(err)))
			end
		end
	end

	return Register, Dispatch
end

-- === Invoke Registry ==========================================================

--[[
	NewInvokeRegistry() -> RegisterHandler, DispatchInvoke

	Invoke only supports a single handler per eventName
	since a RemoteFunction must return one value — multi-handler doesn't make sense here
	registering again = warn + replace (intentional)

	DispatchInvoke uses pcall — a handler error returns nil instead of crashing the server
]]
function NetworkCore.NewInvokeRegistry()
	local registry: {[string]: (Player, ...any) -> any} = {}

	local function RegisterHandler(eventName: string, handler): () -> ()
		NetworkCore.ValidateEventName(eventName, "NetworkCore.NewInvokeRegistry.RegisterHandler")
		assert(type(handler) == "function",
			"[NetworkCore] handler must be a function")

		if registry[eventName] then
			warn(string.format(
				"%s Duplicate invoke handler for '%s' — replacing previous",
				PREFIX, eventName
			))
		end

		registry[eventName] = handler

		local disconnected = false
		return function()
			if disconnected then return end
			disconnected = true
			if registry[eventName] == handler then
				registry[eventName] = nil
			end
		end
	end

	local function DispatchInvoke(eventName: string, ...)
		NetworkCore.ValidateEventName(eventName, "NetworkCore.NewInvokeRegistry.DispatchInvoke")
		local handler = registry[eventName]

		if not handler then
			warn(string.format("%s No invoke handler for: %s", PREFIX, eventName))
			return nil
		end

		local ok, result = pcall(handler, ...)
		if not ok then
			warn(string.format("%s Invoke handler error [%s]: %s", safe(PREFIX), safe(eventName), safe(result)))
			return nil
		end

		return result
	end

	return RegisterHandler, DispatchInvoke
end

return NetworkCore