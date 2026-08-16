--[[
	JanitorTest — manual smoke test for AetherShared.Utils.Janitor.
	Disabled by default (same convention as TestInspector / NetworkInspector).
	Enable and run in a playtest, or paste into command bar, to verify.
]]

local RS = game:GetService("ReplicatedStorage")
local Janitor = require(RS.AetherShared.Utils.Janitor)

local results = {}
local function check(name, cond)
	table.insert(results, string.format("[%s] %s", cond and "PASS" or "FAIL", name))
end

-- 1) Instance -> infers Destroy
do
	local j = Janitor.new()
	local part = Instance.new("Part")
	j:Add(part)
	j:Cleanup()
	check("Instance infers Destroy", part.Parent == nil and not part:IsDescendantOf(game))
end

-- 2) RBXScriptConnection -> infers Disconnect
do
	local j = Janitor.new()
	local bindable = Instance.new("BindableEvent")
	local conn = bindable.Event:Connect(function() end)
	j:Add(conn)
	j:Cleanup()
	check("Connection infers Disconnect", conn.Connected == false)
	bindable:Destroy()
end

-- 3) function -> called directly
do
	local j = Janitor.new()
	local called = false
	j:Add(function() called = true end)
	j:Cleanup()
	check("Function called on cleanup", called == true)
end

-- 4) table with :Destroy -> infers Destroy
do
	local j = Janitor.new()
	local destroyed = false
	local obj = { Destroy = function(self) destroyed = true end }
	j:Add(obj)
	j:Cleanup()
	check("Table with Destroy method", destroyed == true)
end

-- 5) explicit methodName
do
	local j = Janitor.new()
	local stopped = false
	local obj = { Stop = function(self) stopped = true end }
	j:Add(obj, "Stop")
	j:Cleanup()
	check("Explicit methodName used", stopped == true)
end

-- 6) indexed Add replaces old one on re-Add
do
	local j = Janitor.new()
	local firstDestroyed = false
	local secondDestroyed = false
	local first = { Destroy = function() firstDestroyed = true end }
	local second = { Destroy = function() secondDestroyed = true end }
	j:Add(first, nil, "slot")
	j:Add(second, nil, "slot") -- should clean `first` immediately
	check("Indexed Add cleans previous occupant", firstDestroyed == true and secondDestroyed == false)
	j:Cleanup()
	check("Indexed Add cleans current occupant on Cleanup", secondDestroyed == true)
end

-- 7) Remove(index) cleans just that one, leaves rest
do
	local j = Janitor.new()
	local aDestroyed, bDestroyed = false, false
	local a = { Destroy = function() aDestroyed = true end }
	local b = { Destroy = function() bDestroyed = true end }
	j:Add(a, nil, "a")
	j:Add(b, nil, "b")
	j:Remove("a")
	check("Remove cleans only targeted index", aDestroyed == true and bDestroyed == false)
	j:Cleanup()
	check("Remaining indexed item cleaned on Cleanup", bDestroyed == true)
end

-- 8) Cleanup() does not destroy the Janitor itself (reusable)
do
	local j = Janitor.new()
	local n = 0
	j:Add(function() n += 1 end)
	j:Cleanup()
	j:Add(function() n += 1 end)
	j:Cleanup()
	check("Janitor reusable after Cleanup", n == 2)
end

-- 9) Destroy() cleans and marks unusable
do
	local j = Janitor.new()
	local cleaned = false
	j:Add(function() cleaned = true end)
	j:Destroy()
	local ok = pcall(function() j:Add(function() end) end)
	check("Destroy cleans pending items", cleaned == true)
	check("Destroy makes Janitor unusable", ok == false)
end

local failed = 0
for _, line in ipairs(results) do
	if line:sub(1, 6) == "[FAIL]" then
		failed += 1
	end
end

print(string.format("[JanitorTest] %d/%d passed", #results - failed, #results))
print(table.concat(results, "\n"))

if failed > 0 then
	warn(string.format("[JanitorTest] %d check(s) FAILED", failed))
end
