-- ==================================================================
--  Fixed-window rate limiter
--
--  config shape (from NetworkConfig.RateLimit):
--    {
--      Default = { limit = N, window = N },
--      Overrides = { ["EventName"] = { limit = N, window = N } },
--    }
--
--  When blocked, fire BindableEvent "RateLimit.Blocked" with:
--    { player, eventName, limit, window }
--  Let the server handle the rest as needed (log, kick, ban, etc.)
-- ==================================================================

local Players = game:GetService("Players")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Logger = require(RS.AetherShared.Utils.Logger)

local RateLimit = {}

-- == Blocked event =================================================
-- BindableEvent for allowing external systems to subscribe.
-- Creates a lazy event once when Create() is called for the first time.
local _blockedEvent = nil

local function getBlockedEvent()
	if _blockedEvent then return _blockedEvent end

	local Events = SSS.AetherSystems.Events
	local existing = Events:FindFirstChild("RateLimit.Blocked")

	if existing then
		_blockedEvent = existing
	else
		local be = Instance.new("BindableEvent")
		be.Name = "RateLimit.Blocked"
		be.Parent = Events
		_blockedEvent = be
	end

	return _blockedEvent
end

-- == Factory =======================================================

function RateLimit.Create(config)
	local buckets = {}

	-- Cleanup buckets are created when the player exits to prevent memory leaks.
	Players.PlayerRemoving:Connect(function(player)
		local prefix = tostring(player.UserId) .. ":"

		for key in pairs(buckets) do
			if key:sub(1, #prefix) == prefix then
				buckets[key] = nil
			end
		end
	end)

	return function(packet, next)

		-- == Resolve rule: Override → Default ======================
		local rule = (config.Overrides and config.Overrides[packet.eventName])
			or config.Default

		if not rule then
			Logger:Warn(
				"RateLimit",
				"No rule found for event: " .. tostring(packet.eventName)
			)

			next()
			return
		end

		-- Disabled event
		if rule.limit <= 0 then
			Logger:Warn(
				"RateLimit",
				string.format(
					"Blocked by config | event=%s playerId=%s",
					tostring(packet.eventName),
					tostring(packet.player and packet.player.UserId)
				)
			)

			getBlockedEvent():Fire({
				player = packet.player,
				eventName = packet.eventName,
				limit = rule.limit,
				window = rule.window,
			})

			return
		end

		local key = tostring(packet.player.UserId) .. ":" .. packet.eventName
		local currentTime = os.clock()

		local bucket = buckets[key]

		if not bucket then
			bucket = {
				count = 0,
				start = currentTime,
			}

			buckets[key] = bucket
		end

		-- Reset window
		if currentTime - bucket.start > rule.window then
			bucket.count = 0
			bucket.start = currentTime
		end

		bucket.count += 1

		if bucket.count > rule.limit then
			Logger:Warn(
				"RateLimit",
				string.format(
					"Blocked | player: %s | event: %s | %d/%d per %ds",
					packet.player.Name,
					packet.eventName,
					bucket.count,
					rule.limit,
					rule.window
				)
			)

			getBlockedEvent():Fire({
				player = packet.player,
				eventName = packet.eventName,
				limit = rule.limit,
				window = rule.window,
			})

			return
		end

		next()
	end
end

return RateLimit