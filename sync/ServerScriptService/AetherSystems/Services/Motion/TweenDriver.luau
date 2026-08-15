--[[
	TweenDriver ServerSide Entry Point
	
	Single module for all server-initiated tween operations.
	Replaces: Global.TweenModel / Global.BaseTween / BaseTween module / Tween module

	USAGE:
	local TweenDriver = require(path.to.TweenDriver)

	-- Tween a Model or BasePart to a CFrame  (server fires to client plays)
	TweenDriver.Move(instance, {
		Goal = CFrame.new(0, 10, 0),
		Duration = 0.8,
		Wait = true,
		Style = Enum.EasingStyle.Bounce,   -- optional, default Sine
		Direction = Enum.EasingDirection.Out,   -- optional, default InOut
	})

	-- Tween any property on a BasePart/Instance  (server fires to client plays)
	TweenDriver.Property(instance, {
		Property = "Transparency",
		Goal = 1,
		Duration = 0.5,
		Wait = false,
		Style = Enum.EasingStyle.Linear,
		Direction = Enum.EasingDirection.In,
		Proximity = 150,   -- optional: only fire to players within N studs (BasePart only)
	})

	-- Tween any property locally on the server (no client involved)
	TweenDriver.Local(instance, {
		Property = "Transparency",
		Goal = 0,
		Duration = 1,
		Wait = true,
	})

	-- Convenience wrappers (same as Move but easing preset)
	TweenDriver.MoveBounce(instance, goal, duration, wait)
	TweenDriver.MoveLinear(instance, goal, duration, wait)
]]


local TweenDriver = {}

TweenDriver.Descriptor = {
	Name = "Motion",
	Dependencies = {"Network"},
}

-- === Services ==============================================================

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local NetworkCore = require(RS.AetherShared.Utils.NetworkCore)
local Logger = require(RS.AetherShared.Utils.Logger)
local MotionRegistry = require(script.Parent:WaitForChild("MotionRegistry"))
local _Network = nil

-- Local() tweens run entirely server-side, so unlike Move/Property (which
-- replicate to clients) we hold a direct reference and can actually halt
-- playback on Cancel instead of only clearing registry state.
local _localTweens = {}

function TweenDriver.Init(services)
	_Network = services and services.Network
	if not _Network then
		Logger:Warn("TweenDriver", "Network service not provided via services; network calls will be no-ops")
	end
end

-- Defaults 
local DEFAULT_STYLE = Enum.EasingStyle.Sine
local DEFAULT_DIRECTION = Enum.EasingDirection.InOut
local DEFAULT_PROXIMITY = 100   -- studs; used by Property() for BaseParts

-- === Types ================================================================
type MoveConfig = {
	Goal: CFrame | Vector3,
	Duration: number,
	Wait: boolean?,
	Style: Enum.EasingStyle?,
	Direction: Enum.EasingDirection?,
	Relative: boolean?,
}

type PropertyConfig = {
	Property: string,
	Goal: any,
	Duration: number,
	Wait: boolean?,
	Style: Enum.EasingStyle?,
	Direction: Enum.EasingDirection?,
	Proximity: number?,
}

type LocalConfig = {
	Property: string,
	Goal: any,
	Duration: number,
	Wait: boolean?,
	Style: Enum.EasingStyle?,
	Direction: Enum.EasingDirection?,
}

-- === Helpers ================================================================

local function resolveStyle(cfg)
	return (cfg.Style or DEFAULT_STYLE)
end

local function resolveDirection(cfg)
	return (cfg.Direction or DEFAULT_DIRECTION)
end

-- Snap a Model/BasePart to a CFrame after a tween (authoritative server position)
local function snapPosition(instance, goal)
	if instance:IsA("Model") then
		instance:PivotTo(goal)
	elseif instance:IsA("BasePart") then
		instance.CFrame = goal
	end
end

local function getCFrame(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return instance.CFrame
end

local function isValidInstance(instance)
	if not instance then return false end
	if instance:IsA("BasePart") then return true end
	if instance:IsA("Model") and instance.PrimaryPart then return true end
	return false
end

-- === Public API ============================================================

--[[ 
	TweenDriver.Move(instance, config)

	Fires RemoteEvent so every client plays a CFrame tween on a Model or BasePart.
	After the tween the server snaps the instance to the goal for authority.

	config:
		Goal      CFrame or Vector3        (required)
		Duration  number   seconds         (required)
		Wait      bool     block thread?   (default false)
		Style     EasingStyle              (default Sine)
		Direction EasingDirection          (default InOut)
]]

function TweenDriver.Move(instance: Instance, config: MoveConfig)

	if not isValidInstance(instance) then
		Logger:Warn("TweenDriver.Move", "Invalid instance for tween")
		return
	end

	assert(typeof(config.Goal) == "CFrame" or typeof(config.Goal) == "Vector3", "[TweenDriver.Move] config.Goal must be CFrame or Vector3")
	assert(type(config.Duration) == "number", "[TweenDriver.Move] config.Duration must be a number")

	local easingData = {
		Style = resolveStyle(config),
		Direction = resolveDirection(config),
	}

	local goal = config.Goal
	if typeof(goal) == "Vector3" then
		if config.Relative then
			-- preserve orientation, add relative offset to current CFrame
			local current = getCFrame(instance)
			goal = current * CFrame.new(goal)
		else
			local current = getCFrame(instance)
			goal = CFrame.new(goal) * (current - current.Position)
		end
	end

	local token = MotionRegistry.Start(instance, config.Duration, function(inst)
		snapPosition(inst, goal)
	end)

	if not token then
		Logger:Warn("TweenDriver", string.format("Tween already active: %s", instance:GetFullName()))
		task.wait() -- yield so a caller retrying in a tight loop can't starve the scheduler
		return nil
	end
	
	-- fire to clients and register lifecycle; non-blocking
	if _Network then
		NetworkCore.Trace({
			Direction = "SEND",
			Event = "Motion.Tween",
			Target = "ALL",

			Meta = {
				Object = instance.Name,
				Path = instance:GetFullName(),
				Goal = tostring(goal),
				Duration = config.Duration,
			}
		})

		_Network.FireAll("Motion.Tween", instance, goal, config.Duration, easingData)
	else
		Logger:Warn("TweenDriver", "Network service missing")
	end

	if config.Wait then
		while MotionRegistry.IsActive(instance, token) do
			task.wait()
		end
	end

	return {
		Cancel = function() MotionRegistry.Cancel(instance) end,
	}
end

--[[
	TweenDriver.Cancel(instance)

	Force-clears any in-progress tween for this instance, immediately
	unblocking any thread currently parked in a Wait = true Move() call.
	Use this to interrupt a tween from outside the call that started it.
]]
function TweenDriver.Cancel(instance: Instance)
	local cancelled = MotionRegistry.Cancel(instance)

	local localTween = _localTweens[instance]
	if localTween then
		_localTweens[instance] = nil
		if localTween.PlaybackState == Enum.PlaybackState.Playing then
			localTween:Cancel()
		end
		cancelled = true
	end

	return cancelled
end

--[[
	TweenDriver.MoveBounce(instance, goal, duration, wait)

	Convenience wrapper around Move() with Bounce/Out easing preset.
]]
function TweenDriver.MoveBounce(instance: Instance, goal: CFrame | Vector3, duration: number, wait: boolean?)
	return TweenDriver.Move(instance, {
		Goal = goal,
		Duration = duration,
		Wait = wait,
		Style = Enum.EasingStyle.Bounce,
		Direction = Enum.EasingDirection.Out,
	})
end

--[[
	TweenDriver.MoveLinear(instance, goal, duration, wait)

	Convenience wrapper around Move() with Linear easing preset.
]]
function TweenDriver.MoveLinear(instance: Instance, goal: CFrame | Vector3, duration: number, wait: boolean?)
	return TweenDriver.Move(instance, {
		Goal = goal,
		Duration = duration,
		Wait = wait,
		Style = Enum.EasingStyle.Linear,
		Direction = Enum.EasingDirection.InOut,
	})
end

--[[
	TweenDriver.Property(instance, config)

	Fires RemoteEvent so clients play a tween on any tweenable property.
	For BaseParts the fire can be proximity limited (players within Proximity studs).

	config:
		Property  string   property name    (required)
		Goal      any      target value     (required)
		Duration  number   seconds          (required)
		Wait      bool     block thread?    (default false)
		Style     EasingStyle               (default Sine)
		Direction EasingDirection           (default InOut)
		Proximity number   studs (BasePart) (default 100, nil = FireAllClients)
]]
function TweenDriver.Property(instance: Instance, config: PropertyConfig)
	assert(type(config.Property) == "string", "[TweenDriver.Property] config.Property must be a string")
	assert(config.Goal ~= nil, "[TweenDriver.Property] config.Goal is required")
	assert(type(config.Duration) == "number", "[TweenDriver.Property] config.Duration must be a number")

	local style = resolveStyle(config)
	local direction = resolveDirection(config)
	local easingData = { Style = style, Direction = direction }

	local targetPosition = nil
	if instance:IsA("BasePart") then
		targetPosition = instance.Position
	elseif instance:IsA("Light") or instance:IsA("Attachment") or instance:IsA("Sound") then
		local parentPart = instance:FindFirstAncestorWhichIsA("BasePart")
		if parentPart then
			targetPosition = parentPart.Position
		end
	end

	local token = MotionRegistry.Start(instance, config.Duration, function(inst)
		if inst and inst:IsA("BasePart") and config.Property and config.Goal ~= nil then
			pcall(function()
				inst[config.Property] = config.Goal
			end)
		end
	end)

	if not token then
		Logger:Warn("TweenDriver", string.format("Tween already active: %s", instance:GetFullName()))
		task.wait()
		return nil
	end

	local range = config.Proximity or DEFAULT_PROXIMITY
	if targetPosition and range then
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and (targetPosition - hrp.Position).Magnitude <= range then
					if _Network then
						_Network.Fire(player, "Motion.Property", instance, config.Property, config.Goal, config.Duration, easingData)
					else
						Logger:Warn("TweenDriver", "FirePropertyToPlayer called but Network service missing")
					end
				end
		end
	else
		if _Network then
			_Network.FireAll("Motion.Property", instance, config.Property, config.Goal, config.Duration, easingData)
		else
			Logger:Warn("TweenDriver", "FireProperty called but Network service missing")
		end
	end

	if config.Wait then
		while MotionRegistry.IsActive(instance, token) do
			task.wait()
		end
	end

	return {
		Cancel = function()
			MotionRegistry.Cancel(instance)
		end,
	}
end

--[[
	TweenDriver.Local(instance, config)

	Plays a tween locally on the server; no client replication involved.
	Use this for serverside objects the client never sees
	(e.g. invisible sensors, server only models).

	config:
		Property  string   property name    (required)
		Goal      any      target value     (required)
		Duration  number   seconds          (required)
		Wait      bool     block thread?    (default false)
		Style     EasingStyle              (default Sine)
		Direction EasingDirection          (default InOut)
]]
function TweenDriver.Local(instance: Instance, config: LocalConfig)
	assert(type(config.Property) == "string", "[TweenDriver.Local] config.Property must be a string")
	assert(config.Goal ~= nil, "[TweenDriver.Local] config.Goal is required")
	assert(type(config.Duration) == "number", "[TweenDriver.Local] config.Duration must be a number")

	local token = MotionRegistry.Start(instance, config.Duration, nil)
	if not token then
		Logger:Warn("TweenDriver", string.format("Tween already active: %s", instance:GetFullName()))
		task.wait()
		return nil
	end

	local info  = TweenInfo.new(config.Duration, resolveStyle(config), resolveDirection(config))
	local tween = TweenService:Create(instance, info, {[config.Property] = config.Goal})

	_localTweens[instance] = tween

	tween.Completed:Once(function()
		if _localTweens[instance] == tween then
			_localTweens[instance] = nil
		end
	end)

	tween:Play()

	if config.Wait then
		while MotionRegistry.IsActive(instance, token) and tween.PlaybackState == Enum.PlaybackState.Playing do
			task.wait()
		end
	end

	return tween
end

return TweenDriver