--[[
	Generic Push Door CollectionService tag: "Generic_Door"
	Uses TweenDriver for all movement.
]]
local Module = {}

-- Descriptor for resolver
Module.Descriptor = {
	Name = "Doors",
	Dependencies = { "Motion" },
}

local function createDoorModule(Motion)
	local CollectionService = game:GetService("CollectionService")

	local Door = {}
	Door.__index = Door
	Door.tagName = "Generic_Door"

	local BACK_OUT = {Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out}
	local function move(instance, goalCFrame, duration, shouldWait)
		Motion.Move(instance, {
			Goal = goalCFrame,
			Duration = duration,
			Wait = shouldWait,
			Style = BACK_OUT.Style,
			Direction = BACK_OUT.Direction,
		})
	end

	function Door.new(door)
		local self = setmetatable({}, Door)
		self.door = door
		self.debounce = false
		self.state = false
		self.clickDet = door.ClickDetector and door.ClickDetector.MouseClick:Connect(function(...)
			self:Toggle(...)
		end)
		return self
	end

	function Door:Toggle()
		if self.debounce then return end
		self.debounce = true

		if not self.state then
			if self.door:FindFirstChild("LeftDoor") then
				move(self.door.LeftDoor.Door.Model, self.door.LeftDoor.Door.TGP.CFrame, .5, false)
				move(self.door.RightDoor.Door.Model,self.door.RightDoor.Door.TGP.CFrame, .5, false)
				task.wait(.5)
				if self.door.Frame and self.door.Frame.Open then pcall(function() self.door.Frame.Open:Play() end) end
				move(self.door.LeftDoor.Door, self.door.LeftDoor.TGP.CFrame, math.random(110,130)/100, false)
				move(self.door.RightDoor.Door, self.door.RightDoor.TGP.CFrame, math.random(110,130)/100, false)
				task.wait(1.3)
				move(self.door.LeftDoor.Door.Model, self.door.LeftDoor.Door.ORG.CFrame, .5, false)
				move(self.door.RightDoor.Door.Model, self.door.RightDoor.Door.ORG.CFrame, .5, false)
			else
				move(self.door.Door.Model, self.door.Door.TGP.CFrame, .5, false)
				task.wait(.5)
				if self.door.Frame and self.door.Frame.Open then pcall(function() self.door.Frame.Open:Play() end) end
				move(self.door.Door, self.door.TGP.CFrame, 1.3, false)
				task.wait(1.3)
				move(self.door.Door.Model, self.door.Door.ORG.CFrame, .5, true)
			end

			task.wait(1.3 + 0.75)
			self.state = true
			self.debounce = false
		else
			if self.door:FindFirstChild("LeftDoor") then
				move(self.door.LeftDoor.Door, self.door.LeftDoor.ORG.CFrame, math.random(110,130)/100, false)
				move(self.door.RightDoor.Door, self.door.RightDoor.ORG.CFrame, math.random(110,130)/100, false)
				if self.door.Frame and self.door.Frame.Close then pcall(function() self.door.Frame.Close:Play() end) end
			else
				if self.door.Frame and self.door.Frame.Close then pcall(function() self.door.Frame.Close:Play() end) end
				move(self.door.Door, self.door.ORG.CFrame, 1.2, false)
			end

			task.wait(1.3 + 0.75)
			self.state = false
			self.debounce = false
		end
	end

	function Door:Cleanup()
		if self.clickDet then
			self.clickDet:Disconnect()
			self.clickDet = nil
		end
	end

	local doors = {}

	local function onDoorAdded(door)
		if door:IsA("Model") then
			doors[door] = Door.new(door)
		end
	end

	local function onDoorRemoved(door)
		if doors[door] then
			doors[door]:Cleanup()
			doors[door] = nil
		end
	end

	-- attach existing
	for _, door in ipairs(CollectionService:GetTagged(Door.tagName)) do
		onDoorAdded(door)
	end

	CollectionService:GetInstanceAddedSignal(Door.tagName):Connect(onDoorAdded)
	CollectionService:GetInstanceRemovedSignal(Door.tagName):Connect(onDoorRemoved)

	return {
		CleanupAll = function()
			for d, obj in pairs(doors) do
				obj:Cleanup()
			end
		end
	}
end

-- Init entrypoint. Accepts optional services table for migration (services.Motion)
function Module.Init(services)
	local Motion
	if services and services.Motion then
		Motion = services.Motion
	else
		local Loader = require(game:GetService("ServerScriptService").AetherSystems.Core.AetherLoader)
		Motion = Loader.Get("Motion")
	end

	if not Motion then error("[Doors] Motion system not available") end
	createDoorModule(Motion)
end

return Module