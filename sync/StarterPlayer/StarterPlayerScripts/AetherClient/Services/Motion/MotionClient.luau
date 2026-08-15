--[[
	TweenClient Client-Side Motion Handler
	Aether Network System

	Listens for events from the server and plays smooth TweenService animations on the client

	Just flip MotionConfig.USE_NETWORK — no need to touch this script
	Do NOT call this module directly. Auto-started by AetherClientLoader.
]]

local MotionClient = {}

-- === Dependency Declaration ==================================================

-- AetherClientLoader guarantees Network.Init() finishes before MotionClient.Init()
-- Loader injects services.Network directly into Init, no WaitForChild needed
MotionClient.Dependencies = { "Network" }

-- === Services ================================================================

local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Logger = require(RS.AetherShared.Utils.Logger)
local Janitor = require(RS.AetherShared.Utils.Janitor)

-- === Config ==================================================================

-- === State ===================================================================

MotionClient.Ready = false
local queue = {}

-- === Helpers =================================================================

--[[
	applyMove plays a CFrame tween on a Model or BasePart
	Uses a CFrameValue as a proxy since TweenService doesn't support Model CFrame directly
]]
local function applyMove(instance, goalCFrame, duration, style, direction)
	local isModel = instance:IsA("Model") and instance.PrimaryPart ~= nil
	local isBasePart = instance:IsA("BasePart")

	if not isModel and not isBasePart then return end

	local function setCFrame(cf)
		if not instance or not instance.Parent then return end 
		if isModel then 
			if instance.PrimaryPart then instance:PivotTo(cf) end
		else 
			instance.CFrame = cf 
		end
	end

	local function getCFrame()
		if isModel then return instance:GetPrimaryPartCFrame() else return instance.CFrame end
	end

	local j = Janitor.new()

	local proxy = j:Add(Instance.new("CFrameValue"))
	proxy.Value = getCFrame()

	j:Add(proxy:GetPropertyChangedSignal("Value"):Connect(function()
		if not instance or not instance.Parent then
			j:Destroy()
			return
		end
		setCFrame(proxy.Value)
	end))

	j:Add(instance.AncestryChanged:Connect(function(_, parent)
		if not parent then
			j:Destroy()
		end
	end))

	local tween = j:Add(TweenService:Create(
		proxy,
		TweenInfo.new(duration, style, direction),
		{Value = goalCFrame}
	), "Cancel")
	tween:Play()

	tween.Completed:Once(function()
		j:Destroy()
	end)
end

-- === Handlers ================================================================

local function onTween(instance, goalCFrame, duration, easingData)
	if not instance or not instance.Parent then return end

	local style = Enum.EasingStyle.Sine
	local direction = Enum.EasingDirection.InOut

	if typeof(easingData) == "table" then
		style = easingData.Style or style
		direction = easingData.Direction or direction
	end

	applyMove(instance, goalCFrame, duration, style, direction)
end

local function onTweenProperty(instance, property, goal, duration, easingData)
	if not instance or not instance.Parent then return end

	local style = Enum.EasingStyle.Sine
	local direction = Enum.EasingDirection.InOut

	if typeof(easingData) == "table" then
		style = easingData.Style or style
		direction = easingData.Direction or direction
	end

	pcall(function()
		TweenService:Create(
			instance,
			TweenInfo.new(duration or 1, style, direction),
			{[property] = goal}
		):Play()
	end)
end

-- === Queue ===================================================================

local function enqueue(type_, ...)
	table.insert(queue, { type = type_, args = table.pack(...) })
end

local function flushQueue()
	local pending = queue
	queue = {}

	for _, packet in ipairs(pending) do
		if packet.type == "property" then
			onTweenProperty(table.unpack(packet.args, 1, packet.args.n))
		else
			onTween(table.unpack(packet.args, 1, packet.args.n))
		end
	end
end

-- === Init ====================================================================

function MotionClient.Init(services)
	local Network = services.Network
	assert(Network, "[MotionClient] services.Network is required")

	Network.On("Motion.Tween", function(instance, goalCFrame, duration, easingData)
		if not MotionClient.Ready then
			enqueue("tween", instance, goalCFrame, duration, easingData)
			return
		end
		onTween(instance, goalCFrame, duration, easingData)
	end)

	Network.On("Motion.Property", function(instance, property, goal, duration, easingData)
		if not MotionClient.Ready then
			enqueue("property", instance, property, goal, duration, easingData)
			return
		end
		onTweenProperty(instance, property, goal, duration, easingData)
	end)

	Logger:Info("MotionClient", "Network Layer Enabled")

	MotionClient.Ready = true
	flushQueue()
end

return MotionClient
