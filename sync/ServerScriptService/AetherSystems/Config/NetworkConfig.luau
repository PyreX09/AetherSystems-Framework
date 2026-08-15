-- ==================================================================
--  Network configuration for AetherSystems
--  Used by NetworkServer → RateLimit middleware
-- ==================================================================

local NetworkConfig = {}

-- == Rate Limiting =================================================
--  Default : applied to every event that has no Override
--  Overrides: per-event overrides (optional)
--
--  limit  = max requests allowed within the window
--  window = sliding window duration in seconds

NetworkConfig.RateLimit = {
	Default = {
		limit  = 30,    -- 30 requests ...
		window = 1,    -- ... per second
	},

	Overrides = {
		-- Ex: Events that trigger more frequently than usual, such as position sync.
		-- Ex: Events that require a stricter rate limit, such as purchases.
		-- ["BuyItem"] = { limit = 5, window = 10 },
	},
}

return NetworkConfig
