--[[
	NetworkClient Client-Side Network API
	Aether Network System

	PUBLIC API
	  disconnect = Network.On(eventName, handler)  -> () -> ()
	  Network.FireServer(eventName, ...)
	  Network.Invoke(eventName, ...) -> any
	  Network.IsReady() -> bool
	  Network.Init(services) — called by AetherClientLoader

	MULTI-HANDLER
	  Network.On("PlayerDied", Analytics)
	  Network.On("PlayerDied", Effects)
	  Network.On("PlayerDied", State)
	  every handler is called, each can be disconnected independently
]]

local RS = game:GetService("ReplicatedStorage")

local Logger = require(RS.AetherShared.Utils.Logger)
local Core = require(RS.AetherShared.Utils.NetworkCore)

local NetworkClient = {}

-- === Dependency Declaration ==================================================

NetworkClient.Dependencies = {}

-- === Ready State ==============================================================

local _ready = false

function NetworkClient.IsReady(): boolean
	return _ready
end

-- === Registry ================================================================

local _on, _dispatch = Core.NewRegistry()

-- === Queue ===================================================================

--[[
	buffers packets that arrive before Init finishes (server can fire right after join)

	Structure: { eventName: string, args: table.pack(...) }
	  .eventName = the event name
	  .args      = table.pack(...) — keeps n for a nil-safe unpack
	               so a packet with nil as a middle arg isn't corrupted

	Why not a flat array { eventName, arg1, arg2, ... }:
	  #table in Lua stops counting at the first nil
	  table.unpack(t, 2) without an end index would cut off at the nil
	  args after the nil would disappear silently, without an error
]]
local _queue = {}

-- === On ======================================================================

function NetworkClient.On(eventName: string, handler): () -> ()
	Core.ValidateEventName(eventName, "NetworkClient.On")
	assert(type(handler) == "function",
		"[NetworkClient.On] handler must be a function")

	return _on(eventName, handler)
end

-- === FireServer ==============================================================

function NetworkClient.FireServer(eventName: string, ...)
	Core.ValidateEventName(eventName, "NetworkClient.FireServer")

	Core._log("SEND", eventName, "-> SERVER")
	Core.Remote:FireServer(eventName, ...)
end

-- === Invoke ==================================================================

function NetworkClient.Invoke(eventName: string, ...)
	Core.ValidateEventName(eventName, "NetworkClient.Invoke")

	if not coroutine.isyieldable() then
		error("[NetworkClient.Invoke] Cannot be called from this context (e.g. BindableFunction.OnInvoke or another non-yieldable callback). Wrap the call in task.spawn(function() ... end) instead.", 2)
	end

	Core._log("INVOKE", eventName, "to SERVER")

	local thread = coroutine.running()
	local completed = false

	task.delay(10, function()
		if not completed then
			completed = true
			task.spawn(thread, nil, "TIMEOUT")
		end
	end)

	task.spawn(function(...)
		local success, res = pcall(function(...)
			return Core.Function:InvokeServer(eventName, ...)
		end, ...)

		if not completed then
			completed = true
			if success then
				task.spawn(thread, res, nil)
			else
				task.spawn(thread, nil, "SERVER_ERROR")
			end
		end
	end, ...)

	local data, err = coroutine.yield()

	if err then
		Logger:Warn("NetworkClient", string.format("Invoke '%s' failed: %s", eventName, err))
	end

	return data
end

-- === Flush Queue =============================================================

local function flushQueue()
	task.defer(function()
		local pending = _queue
		_queue = {}

		for _, packet in ipairs(pending) do
			Core._log("FLUSH", packet.eventName, "<- SERVER (queued)")
			-- unpack with n to preserve nil args
			_dispatch(packet.eventName, table.unpack(packet.args, 1, packet.args.n))
		end
	end)
end

-- === Init ====================================================================

function NetworkClient.Init(services)
	Core.Remote.OnClientEvent:Connect(function(eventName, ...)
		if type(eventName) ~= "string" or #eventName == 0 then
			Logger:Warn("NetworkClient", string.format(
				"Rejected packet from server (invalid eventName) %s", 
				tostring(eventName)
				))
			return
		end

		Core.Trace({
			Direction = "RECV",
			Event = eventName,
			Target = "SERVER"
		})

		if not _ready then
			table.insert(_queue, { eventName = eventName, args = table.pack(...) })
			return
		end

		_dispatch(eventName, ...)
	end)

	_ready = true
	flushQueue()

	Logger:Debug("NetworkClient", "Ready")
end

return NetworkClient