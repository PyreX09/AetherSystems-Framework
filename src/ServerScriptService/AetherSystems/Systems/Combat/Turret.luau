--[[
	Turret CollectionService tag: "Turret"

	A turret Model with a "Base" part and a "Head" part. The Head rotates
	to face the nearest player within range that it has a clear line of
	sight to, using:

	  - RaycastUtil : cached, reusable RaycastParams for the LOS check
	  - Motion      : TweenDriver, rotates Head to face the target
	  - Janitor     : per-turret cleanup when the turret leaves the game
	  - Logger      : boot summary + target acquired/lost transitions
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.AetherShared.Utils.Logger)
local Janitor = require(ReplicatedStorage.AetherShared.Utils.Janitor)
local RaycastUtil = require(ReplicatedStorage.AetherShared.Utils.RaycastUtil)

local Module = {}

Module.Descriptor = {
	Name = "Turret",
	Dependencies = { "Motion" },
}

local TAG = "Turret"
local TAG_NAME = "Turret"

local RANGE = 60
local SCAN_INTERVAL = 0.3
local TRACK_DURATION = 0.25
local LOS_PARAMS_NAME = "Turret.LOS"

local function createTurretModule(Motion)
	-- Single shared RaycastParams reused for every LOS check. Updated in
	-- place per scan (Update() then an immediate Raycast, no yields between
	-- the two calls), so it never needs to be re-created.
	if not RaycastUtil.Exists(LOS_PARAMS_NAME) then
		RaycastUtil.Register(LOS_PARAMS_NAME, {
			FilterType = Enum.RaycastFilterType.Exclude,
			FilterDescendantsInstances = {},
		})
	end

	local turrets = {} -- [model] = Janitor

	-- Finds the nearest player within RANGE that has a clear line of sight
	-- from `head`. Returns the player's HumanoidRootPart, or nil.
	local function findNearestVisiblePlayer(head: BasePart, turretModel: Model)
		local nearest, nearestDist = nil, RANGE

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not hrp then
				continue
			end

			local distance = (hrp.Position - head.Position).Magnitude
			if distance > nearestDist then
				continue
			end

			RaycastUtil.Update(LOS_PARAMS_NAME, {
				FilterDescendantsInstances = { turretModel, character },
			})
			local params = RaycastUtil.Get(LOS_PARAMS_NAME)

			local direction = hrp.Position - head.Position
			local hit = workspace:Raycast(head.Position, direction, params)

			if not hit then
				nearest, nearestDist = hrp, distance
			end
		end

		return nearest
	end

	local function trackTurret(turretModel: Model)
		local base = turretModel:FindFirstChild("Base")
		local head = turretModel:FindFirstChild("Head")

		if not (base and head and head:IsA("BasePart")) then
			Logger:Warn(TAG, "missing Base/Head, skipping", turretModel:GetFullName())
			return
		end

		local janitor = Janitor.new()
		turrets[turretModel] = janitor

		-- Cooperative stop flag for the scan loop below. Registered with the
		-- janitor as a plain function (Janitor calls functions directly).
		local scanning = true
		janitor:Add(function()
			scanning = false
		end)

		local currentTarget: Instance? = nil

		task.spawn(function()
			while scanning do
				local targetHrp = findNearestVisiblePlayer(head, turretModel)
				local targetCharacter = targetHrp and targetHrp.Parent or nil

				if targetCharacter ~= currentTarget then
					if targetCharacter then
						Logger:Info(TAG, turretModel.Name, "acquired target", targetCharacter.Name)
					else
						Logger:Info(TAG, turretModel.Name, "lost target")
					end
					currentTarget = targetCharacter
				end

				if targetHrp then
					local headPos = head.Position
					local lookAt = CFrame.lookAt(
						headPos,
						Vector3.new(targetHrp.Position.X, headPos.Y, targetHrp.Position.Z)
					)

					Motion.Move(head, {
						Goal = lookAt,
						Duration = TRACK_DURATION,
						Wait = false,
						Style = Enum.EasingStyle.Linear,
						Direction = Enum.EasingDirection.InOut,
					})
				end

				task.wait(SCAN_INTERVAL)
			end
		end)

		janitor:Add(turretModel.AncestryChanged:Connect(function(_, parent)
			if parent then
				return
			end
			Logger:Info(TAG, turretModel.Name, "removed, cleaning up")
			turrets[turretModel] = nil
			janitor:Destroy()
		end))
	end

	-- attach existing
	for _, turretModel in CollectionService:GetTagged(TAG_NAME) do
		trackTurret(turretModel)
	end

	CollectionService:GetInstanceAddedSignal(TAG_NAME):Connect(trackTurret)

	Logger:Info(TAG, "initialized, tracking", #CollectionService:GetTagged(TAG_NAME), "turret(s)")

	return {
		Count = function()
			local n = 0
			for _ in turrets do
				n += 1
			end
			return n
		end,
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

	if not Motion then
		Logger:Fatal(TAG, "Motion system not available")
	end

	createTurretModule(Motion)
end

return Module
