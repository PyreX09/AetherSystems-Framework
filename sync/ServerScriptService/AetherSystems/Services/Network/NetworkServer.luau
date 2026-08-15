local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Logger = require(RS.AetherShared.Utils.Logger)
local Core = require(RS.AetherShared.Utils.NetworkCore)

local RateLimit = require(script.RateLimit)
local NetConfig = require(SSS.AetherSystems.Config.NetworkConfig)

local NetworkServer = {}

NetworkServer.Descriptor = {
	Name = "Network",
	Dependencies = {}
}

local _on, _dispatch = Core.NewRegistry()
local _handle, _dispatchInvoke = Core.NewInvokeRegistry()

local _middlewares = {}
local _initialized = false
local RateLimiter

-- ── Middleware registration ───────────────────────────────────────

function NetworkServer.Use(fn)
	table.insert(_middlewares, fn)

	return function()
		for i = #_middlewares, 1, -1 do
			if _middlewares[i] == fn then
				table.remove(_middlewares, i)
				break
			end
		end
	end
end

-- ── Middleware runner ─────────────────────────────────────────────

local function runMiddleware(packet, final, onFailure)
	local i = 0

	local function step()
		i += 1

		if i > #_middlewares then
			final()
			return
		end

		local middleware = _middlewares[i]
		local called = false

		local function next()
			if called then
				Logger:Warn("Network", "middleware called next() multiple times")
				return
			end

			called = true
			step()
		end

		local ok, err = pcall(middleware, packet, next)

		if not ok then
			Logger:Warn(
				"Network",
				string.format(
					"MiddlewareError | event=%s playerId=%s err=%s",
					tostring(packet.eventName),
					tostring(packet.player and packet.player.UserId),
					tostring(err)
				)
			)

			if onFailure then
				onFailure("MIDDLEWARE_ERROR")
			end
			return
		end
	end

	step()
end

-- ── Public API ────────────────────────────────────────────────────

function NetworkServer.Fire(player, eventName, ...)
	assert(player and player:IsA("Player"), "[NetworkServer.Fire] Invalid player")
	Core.ValidateEventName(eventName, "NetworkServer.Fire")

	Core.Trace({
		Direction = "SEND",
		Event = eventName,
		Target = player and player.Name or "ALL"
	})

	Core.Remote:FireClient(player, eventName, ...)
end

function NetworkServer.FireAll(eventName, ...)
	Core.ValidateEventName(eventName, "NetworkServer.FireAll")

	Core.Trace({
		Direction = "SEND",
		Event = eventName,
		Target = "ALL"
	})

	Core.Remote:FireAllClients(eventName, ...)
end

function NetworkServer.On(eventName, handler)
	return _on(eventName, handler)
end

function NetworkServer.Handle(eventName, handler)
	return _handle(eventName, handler)
end

function NetworkServer.Trace(data)
	Core.Trace(data)
end

-- ── Init ──────────────────────────────────────────────────────────

function NetworkServer.Init(services)
	if _initialized then return end
	_initialized = true

	RateLimiter = RateLimit.Create(NetConfig.RateLimit)

	NetworkServer.Use(RateLimiter)

	Core.Remote.OnServerEvent:Connect(function(player, eventName, ...)
		if type(eventName) ~= "string"
			or eventName == ""
			or #eventName > Core.MAX_EVENT_NAME_LEN then

			Logger:Warn(
				"NetworkServer",
				string.format(
					"Rejected packet from %s, invalid eventName: %s",
					player.Name,
					tostring(eventName)
				)
			)

			return
		end

		local packet = {
			player = player,
			eventName = eventName,
			args = table.pack(...),
		}

		Core.Trace({
			Direction = "RECV",
			Event = eventName,
			Target = player.Name
		})

		runMiddleware(packet, function()
			_dispatch(
				eventName,
				player,
				table.unpack(packet.args, 1, packet.args.n)
			)
		end)
	end)

	Core.Function.OnServerInvoke = function(player, eventName, ...)
		if type(eventName) ~= "string"
			or eventName == ""
			or #eventName > Core.MAX_EVENT_NAME_LEN then

			return nil
		end

		local packet = {
			player = player,
			eventName = eventName,
			args = table.pack(...),
		}

		local returnPack
		local isBlocked = false

		runMiddleware(packet, function()
			returnPack = table.pack(pcall(function()
				return _dispatchInvoke(
					eventName,
					player,
					table.unpack(packet.args, 1, packet.args.n)
				)
			end))
		end, function(reason)
			isBlocked = true
		end)

		if isBlocked then
			return nil
		end

		if returnPack and returnPack[1] then
			return table.unpack(returnPack, 2, returnPack.n)
		else
			local err = returnPack and returnPack[2] or "Unknown error"
			Logger:Warn("NetworkServer", string.format("Invoke handler error [%s]: %s", eventName, tostring(err)))
			return nil
		end
	end

	Logger:Debug("NetworkServer", "Ready")
end

return NetworkServer
