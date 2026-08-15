--[[
	Janitor — general-purpose cleanup tracker.

	local Janitor = require(...)

	local j = Janitor.new()
	j:Add(connection)                  -- infers :Disconnect()
	j:Add(instance)                    -- infers :Destroy()
	j:Add(tbl, "Stop")                 -- explicit method name
	j:Add(fn)                          -- called directly
	j:Add(part, "Destroy", "part")     -- indexed — replacing "part" cleans the old one first

	j:Remove("part")   -- clean + drop one indexed item
	j:Cleanup()         -- clean everything, janitor stays usable
	j:Destroy()         -- Cleanup() + janitor can no longer be used
]]

local Janitor = {}
Janitor.__index = Janitor

local function inferMethod(object)
	if typeof(object) == "RBXScriptConnection" then
		return "Disconnect"
	elseif typeof(object) == "Instance" then
		return "Destroy"
	elseif type(object) == "table" and type(object.Destroy) == "function" then
		return "Destroy"
	end
	return nil
end

local function clean(object, methodName)
	if type(object) == "function" then
		object()
		return
	end

	local method = methodName or inferMethod(object)
	assert(method, "[Janitor] Cannot infer cleanup method for object, pass methodName explicitly")

	object[method](object)
end

function Janitor.new()
	return setmetatable({
		_items = {},    -- unindexed: { [object] = methodName }
		_indexed = {},  -- indexed:   { [key] = { object, methodName } }
	}, Janitor)
end

-- Add(object, methodName?, index?) -> object
function Janitor:Add(object, methodName, index)
	if index ~= nil then
		self:Remove(index)
		self._indexed[index] = { object, methodName }
	else
		self._items[object] = methodName or false
	end

	return object
end

-- Remove(index) — cleans and drops a single indexed item, if present
function Janitor:Remove(index)
	local entry = self._indexed[index]
	if not entry then
		return
	end

	self._indexed[index] = nil
	clean(entry[1], entry[2])
end

-- Cleanup() — cleans every tracked item; janitor remains usable afterward
function Janitor:Cleanup()
	local items = self._items
	self._items = {}
	for object, methodName in pairs(items) do
		clean(object, methodName or nil)
	end

	local indexed = self._indexed
	self._indexed = {}
	for _, entry in pairs(indexed) do
		clean(entry[1], entry[2])
	end
end

-- Destroy() — Cleanup() and mark the janitor unusable
function Janitor:Destroy()
	self:Cleanup()
	self._items = nil
	self._indexed = nil
end

return Janitor
