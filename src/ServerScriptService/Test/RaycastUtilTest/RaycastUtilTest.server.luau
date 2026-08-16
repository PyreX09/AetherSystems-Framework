-- Regression test for AetherShared.Utils.RaycastUtil
-- Proves:
--   1. Get() returns the same RaycastParams object on every call
--   2. Update() mutates that object in place (pre-held references stay in sync)
--   3. Native workspace:Raycast(origin, direction, params) works directly with
--      the object Get() returns, with no wrapper in between
--
-- Run this Script in Studio to re-run the regression checks.
-- Relies on Origin / Target / Obstruction parts under this same folder.

local RaycastUtil = require(game.ReplicatedStorage.AetherShared.Utils.RaycastUtil)
local Logger = require(game.ReplicatedStorage.AetherShared.Utils.Logger)

local TAG = "RaycastUtilTest"

local folder = script.Parent
local Origin = folder.Origin
local Target = folder.Target
local Obstruction = folder.Obstruction

local passed, failed = 0, 0

local function check(name, condition)
    if condition then
        passed += 1
        Logger:Info(TAG, name .. " - PASS")
    else
        failed += 1
        Logger:Error(TAG, name .. " - FAIL")
    end
end

Logger:Begin(TAG)

-- setup: register LOS, excluding only Origin from the ray
RaycastUtil.Register("LOS_Test", {
    FilterType = Enum.RaycastFilterType.Exclude,
    FilterDescendantsInstances = {Origin},
})

-- 1) Get() returns the same object every call
local ref1 = RaycastUtil.Get("LOS_Test")
local ref2 = RaycastUtil.Get("LOS_Test")
check("1. Get() returns same object", ref1 == ref2)

-- keep ref1 (obtained BEFORE Update) to test mutation-in-place
local direction = (Target.Position - Origin.Position)

local hit1 = workspace:Raycast(Origin.Position, direction, ref1)
check("Sanity: first raycast hits Obstruction", hit1 ~= nil and hit1.Instance == Obstruction)

-- 2) Update() mutates the SAME object that ref1 points to
RaycastUtil.Update("LOS_Test", {
    FilterDescendantsInstances = {Origin, Obstruction},
})

local hit2 = workspace:Raycast(Origin.Position, direction, ref1) -- note: still using OLD reference
check("2. Update() reflected on pre-held reference (ref1)", hit2 ~= nil and hit2.Instance == Target)

-- 3) Native workspace:Raycast works directly with a fresh Get() result, no wrapper
local nativeParams = RaycastUtil.Get("LOS_Test")
local hit3 = workspace:Raycast(Origin.Position, direction, nativeParams)
check(
    "3. Native workspace:Raycast works with Get() result",
    hit3 ~= nil and hit3.Instance == Target
)

RaycastUtil.Remove("LOS_Test")

Logger:End(TAG)

if failed == 0 then
    Logger:Info(TAG, ("All checks passed (%d/%d)"):format(passed, passed + failed))
else
    Logger:Error(TAG, ("%d check(s) failed (%d/%d passed)"):format(failed, passed, passed + failed))
end
