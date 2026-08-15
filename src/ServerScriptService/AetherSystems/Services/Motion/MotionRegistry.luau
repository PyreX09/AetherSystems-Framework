local MotionRegistry = {}

local active = {}
local id = 0

function MotionRegistry.Start(instance, duration, onComplete)

	if not instance then
		return false
	end

	if active[instance] then
		return false
	end
	
	id += 1

	local currentId = id
	active[instance] = currentId

	task.delay(duration or 0, function()

		if active[instance] == currentId then
			active[instance] = nil

			if onComplete then
				pcall(onComplete, instance)
			end
		end

	end)

	return currentId
end

function MotionRegistry.IsActive(instance, id)
	return active[instance] == id
end

function MotionRegistry.Cancel(instance)
	if active[instance] then
		active[instance] = nil
		return true
	end
	return false
end

return MotionRegistry